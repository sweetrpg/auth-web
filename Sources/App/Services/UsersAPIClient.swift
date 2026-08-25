import Vapor

/// Calls `users-api`'s `POST /internal/identities/provision` during `/auth/callback` to
/// find-or-create the `User`/`LoginProfile` pair for a verified Auth0 subject - see
/// `sweetrpg/platform`'s `add-users-api-provisioning` design.md. `auth-web` has no end-user
/// bearer token to forward at this point in the flow (it's mid token-exchange), so this call is
/// gated by a shared-secret header instead of a forwarded token, unlike `AuthAPIClient`.
struct UsersAPIClient {
  let request: Request

  private var baseURL: String {
    Environment.get("USERS_API_URL") ?? "http://api-v1.sweetrpg-users.svc.cluster.local:8000"
  }
  private var internalServiceToken: String {
    Environment.get("INTERNAL_SERVICE_TOKEN") ?? ""
  }

  struct ProvisionRequest: Content {
    let subject: String
    let name: String
    let email: String?
  }

  struct ProvisionResponse: Content {
    let userId: String
    let created: Bool
  }

  func provision(subject: String, name: String, email: String?) async throws -> ProvisionResponse {
    try await request.client.post(URI(string: "\(baseURL)/internal/identities/provision")) { req in
      req.headers.add(name: "X-Internal-Service-Token", value: internalServiceToken)
      try req.content.encode(ProvisionRequest(subject: subject, name: name, email: email))
    }.content.decode(ProvisionResponse.self)
  }
}

extension Request {
  var usersAPI: UsersAPIClient { UsersAPIClient(request: self) }
}
