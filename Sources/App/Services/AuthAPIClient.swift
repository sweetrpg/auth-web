import Vapor

/// Calls `auth-api`'s `POST /authz/check` once at login to establish the session's verified
/// roles - see `sweetrpg/platform`'s `split-authz-into-auth-api` change design.md. This app
/// never decodes or verifies the token itself; it passes it straight through and trusts
/// `auth-api`'s answer. Renamed from `UsersAPIClient` when authz moved off `users-api` into its
/// own dedicated service.
struct AuthAPIClient {
  let request: Request

  private var baseURL: String {
    Environment.get("AUTH_API_URL") ?? "http://auth-api.sweetrpg-auth.svc.cluster.local"
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
      // Forward whatever trace context this request already arrived with - never fabricate
      // one. Nothing upstream of this app sets `traceparent` yet, so this is a no-op today;
      // it activates automatically once frontend-side tracing is separately scoped (see
      // sweetrpg/platform's migrate-auth-users-api-to-go change design.md).
      if let traceparent = request.headers.first(name: "traceparent") {
        req.headers.replaceOrAdd(name: "traceparent", value: traceparent)
      }
      try req.content.encode(["service": "platform"])
    }.content.decode(AuthzCheckResponse.self)
  }
}

extension Request {
  var authAPI: AuthAPIClient { AuthAPIClient(request: self) }
}
