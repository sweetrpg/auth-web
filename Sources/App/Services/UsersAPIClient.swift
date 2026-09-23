import Vapor

/// Calls `users-api`'s `POST /internal/identities/provision` during `/auth/callback` to
/// find-or-create the `User`/`LoginProfile` pair for the just-verified Auth0 subject - see
/// `sweetrpg/platform`'s `add-users-api-provisioning` design.md. Presents the same Auth0 access
/// token already used for the `auth-api` authz check as a bearer credential, matching the rest
/// of the platform's `api-client-auth` convention (a forwarded user token, not a shared service
/// secret) - `users-api` independently re-verifies it and derives the subject from the verified
/// token itself, not from a client-supplied value.
struct UsersAPIClient {
  let request: Request

  private var baseURL: String {
    Environment.get("USERS_API_URL") ?? "http://api-v1.sweetrpg-users.svc.cluster.local:8000"
  }

  struct ProvisionRequest: Content {
    let name: String
    let email: String?
  }

  struct ProvisionResponse: Content {
    let userId: String
    let created: Bool
  }

  func provision(accessToken: String, name: String, email: String?) async throws
    -> ProvisionResponse
  {
    try await request.client.post(URI(string: "\(baseURL)/internal/identities/provision")) { req in
      req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
      try req.content.encode(ProvisionRequest(name: name, email: email))
    }.content.decode(ProvisionResponse.self)
  }

  struct LinkStartResponse: Content { let ticket: String }

  /// The caller's Auth0 access token verified fine, but `users-api` has no `LoginProfile` for
  /// that subject yet - there's no existing account to attach a second identity to. Maps to
  /// `users-api`'s `404 {"error":"not_found"}` (see `server/identities.go`), distinct from a
  /// generic transport/server failure.
  struct LinkNoProfileError: Error {}

  /// The link ticket used in a completion call was already used, or has aged past its 5-minute
  /// TTL. Maps to `users-api`'s `410 {"error":"ticket_consumed"}`/`{"error":"ticket_expired"}`.
  struct LinkTicketExpiredError: Error {}

  /// The second identity's `LoginProfile` already belongs to a different `User` - a real,
  /// expected outcome (see design.md's "Conflict rule: reject, never merge"), distinct from a
  /// transport/server failure. Maps to `users-api`'s `409 {"error":"identity_conflict"}`.
  struct LinkConflictError: Error {}

  /// Mints a short-lived, single-use link ticket for the caller's own account via `users-api`'s
  /// `POST /internal/identities/link/start`. Forwards the session's own Auth0 access token as a
  /// bearer credential, same convention as `provision(accessToken:...)` above - `users-api`
  /// verifies it against `auth-api`'s `/authz/check`, then resolves the caller's `User.id` from
  /// their own existing `LoginProfile` server-side. No client-supplied `User.id` and no shared
  /// secret: an earlier draft of this call used a shared `INTERNAL_SERVICE_TOKEN` header per
  /// `link-user-accounts`'s design.md, but that mechanism was removed from `users-api` after its
  /// other callers migrated off it - see the correction in that change's follow-up coordination.
  func linkStart(accessToken: String) async throws -> LinkStartResponse {
    let response = try await request.client.post(
      URI(string: "\(baseURL)/internal/identities/link/start")
    ) { req in
      req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
    }
    switch response.status {
    case .ok: return try response.content.decode(LinkStartResponse.self)
    case .notFound: throw LinkNoProfileError()
    default: throw Abort(response.status)
    }
  }

  struct LinkCompleteRequest: Content { let ticket: String }
  struct LinkCompleteResponse: Content { let userId: String }

  /// Completes a pending link via `users-api`'s `POST /internal/identities/link/complete`,
  /// forwarding the second identity's own Auth0 access token as the bearer credential - both the
  /// call's own authentication and the token `users-api` verifies against `auth-api`'s
  /// `/authz/check` before resolving/attaching the profile, same single-token pattern as
  /// `linkStart` and `provision` above.
  ///
  /// Every non-2xx response from this endpoint carries a JSON `apiv.ErrorVO` body
  /// (`{"error": "<code>", "message": "<string>"}`) - the status code alone is enough to
  /// distinguish the outcomes this client cares about, so the body itself is never parsed. An
  /// earlier version of this method treated any non-`.ok`/non-`.conflict` status as a decode
  /// failure, which would have misclassified `.gone` (expired/consumed ticket) as a generic
  /// "unavailable" failure instead of surfacing it distinctly.
  func linkComplete(ticket: String, accessToken: String) async throws -> LinkCompleteResponse {
    let response = try await request.client.post(
      URI(string: "\(baseURL)/internal/identities/link/complete")
    ) { req in
      req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
      try req.content.encode(LinkCompleteRequest(ticket: ticket))
    }
    switch response.status {
    case .ok: return try response.content.decode(LinkCompleteResponse.self)
    case .conflict: throw LinkConflictError()
    case .gone: throw LinkTicketExpiredError()
    case .notFound: throw LinkNoProfileError()
    default: throw Abort(response.status)
    }
  }
}

extension Request {
  var usersAPI: UsersAPIClient { UsersAPIClient(request: self) }
}
