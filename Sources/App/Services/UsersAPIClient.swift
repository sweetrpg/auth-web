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
}

extension Request {
  var usersAPI: UsersAPIClient { UsersAPIClient(request: self) }
}
