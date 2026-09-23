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

  /// Mints a short-lived, single-use link ticket for the caller's own account via `users-api`'s
  /// `POST /internal/identities/link/start`. Forwards the session's own Auth0 access token as a
  /// bearer credential, same convention as `provision(accessToken:...)` above - `users-api`
  /// verifies it against `auth-api`'s `/authz/check`, then resolves the caller's `User.id` from
  /// their own existing `LoginProfile` server-side. No client-supplied `User.id` and no shared
  /// secret: an earlier draft of this call used a shared `INTERNAL_SERVICE_TOKEN` header per
  /// `link-user-accounts`'s design.md, but that mechanism was removed from `users-api` after its
  /// other callers migrated off it - see the correction in that change's follow-up coordination.
  func linkStart(accessToken: String) async throws -> LinkStartResponse {
    try await request.client.post(URI(string: "\(baseURL)/internal/identities/link/start")) { req in
      req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
    }.content.decode(LinkStartResponse.self)
  }

  struct LinkCompleteRequest: Content { let ticket: String }
  struct LinkCompleteResponse: Content { let userId: String }

  /// The second identity's `LoginProfile` already belongs to a different `User` - a real,
  /// expected outcome (see design.md's "Conflict rule: reject, never merge"), distinct from a
  /// transport/server failure.
  struct LinkConflictError: Error {}

  /// Completes a pending link via `users-api`'s `POST /internal/identities/link/complete`,
  /// forwarding the second identity's own Auth0 access token as the bearer credential - both the
  /// call's own authentication and the token `users-api` verifies against `auth-api`'s
  /// `/authz/check` before resolving/attaching the profile, same single-token pattern as
  /// `linkStart` and `provision` above.
  func linkComplete(ticket: String, accessToken: String) async throws -> LinkCompleteResponse {
    let response = try await request.client.post(
      URI(string: "\(baseURL)/internal/identities/link/complete")
    ) { req in
      req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
      try req.content.encode(LinkCompleteRequest(ticket: ticket))
    }
    if response.status == .conflict { throw LinkConflictError() }
    guard response.status == .ok else { throw Abort(response.status) }
    return try response.content.decode(LinkCompleteResponse.self)
  }
}

extension Request {
  var usersAPI: UsersAPIClient { UsersAPIClient(request: self) }
}
