import Vapor

/// Calls `users-api`'s `POST /authz/check` once at login to establish the session's verified
/// roles - see design.md's "Server-side JWKS verification" decision in platform's
/// add-user-api-authn-authz change. This app never decodes or verifies the token itself; it
/// passes it straight through and trusts `users-api`'s answer.
struct UsersAPIClient {
  let request: Request

  private var baseURL: String {
    Environment.get("USERS_API_URL") ?? "http://users-api.sweetrpg-user.svc.cluster.local"
  }

  struct AuthzCheckResponse: Content {
    let allowed: Bool
    let roles: [String]?
    let sub: String?
  }

  /// `service: "platform"` is a bootstrap check: at login time there's no specific service/action
  /// being guarded yet, only "what are this token's verified roles" - any other consuming service
  /// still makes its own `/authz/check` call scoped to its own name before a privileged action.
  func checkAuthz(accessToken: String) async throws -> AuthzCheckResponse {
    try await request.client.post(URI(string: "\(baseURL)/authz/check")) { req in
      req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
      try req.content.encode(["service": "platform"])
    }.content.decode(AuthzCheckResponse.self)
  }
}

extension Request {
  var usersAPI: UsersAPIClient { UsersAPIClient(request: self) }
}
