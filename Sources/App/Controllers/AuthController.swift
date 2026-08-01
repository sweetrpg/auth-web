import Vapor

/// Sole implementer of the Auth0 Authorization Code flow for the whole suite - see design.md's
/// "auth-web is the sole owner of the Authorization Code exchange" decision in platform's
/// add-user-api-authn-authz change. Every other frontend's "log in" link points at
/// `/auth/login?return_to=<path>` here instead of running its own redirect/callback.
struct AuthController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("auth", "login", use: redirectToAuth0)
    routes.get("auth", "callback", use: callback)
    routes.post("auth", "logout", use: logout)
  }

  private static let returnToSessionKey = "auth_return_to"

  /// Only a same-host, relative path is accepted - an absolute URL in `return_to` would let this
  /// endpoint be used as an open redirect.
  private func sanitizedReturnTo(_ raw: String?) -> String {
    guard let raw, raw.hasPrefix("/"), !raw.hasPrefix("//") else { return "/" }
    return raw
  }

  @Sendable
  func redirectToAuth0(req: Request) async throws -> Response {
    let config = req.application.auth0Config
    guard config.isConfigured else {
      req.logger.warning("AUTH0_DOMAIN/AUTH0_CLIENT_ID not set - cannot start login flow")
      throw Abort(.serviceUnavailable, reason: "Login is not configured")
    }
    struct LoginQuery: Content { let returnTo: String? }
    let query = try req.query.decode(LoginQuery.self)

    let state = [UInt8].random(count: 16).base64String()
    req.session.data["auth_state"] = state
    req.session.data[Self.returnToSessionKey] = sanitizedReturnTo(query.returnTo)
    return req.redirect(to: config.authorizeURL(state: state))
  }

  @Sendable
  func callback(req: Request) async throws -> Response {
    struct CallbackQuery: Content {
      let code: String?
      let state: String?
      let error: String?
    }
    let query = try req.query.decode(CallbackQuery.self)
    let returnTo = req.session.data[Self.returnToSessionKey] ?? "/"
    req.session.data[Self.returnToSessionKey] = nil

    if let error = query.error {
      req.logger.warning("Auth0 callback returned an error: \(error)")
      return req.redirect(to: "\(returnTo)?login_error=1")
    }
    guard let code = query.code, query.state == req.session.data["auth_state"] else {
      req.logger.warning("Auth0 callback missing code or state mismatch")
      return req.redirect(to: "\(returnTo)?login_error=1")
    }
    req.session.data["auth_state"] = nil

    let config = req.application.auth0Config
    struct TokenResponse: Content {
      let accessToken: String
      let idToken: String

      enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case idToken = "id_token"
      }
    }
    let tokenResponse = try await req.client.post(
      URI(string: "https://\(config.domain)/oauth/token"),
      content: [
        "grant_type": "authorization_code",
        "client_id": config.clientID,
        "client_secret": config.clientSecret,
        "code": code,
        "redirect_uri": config.callbackURL,
      ] as [String: String]
    ).content.decode(TokenResponse.self)

    guard let claims = decodeUnverifiedJWTPayload(tokenResponse.idToken),
      let sub = claims["sub"] as? String
    else {
      req.logger.error("Could not decode Auth0 ID token claims")
      return req.redirect(to: "\(returnTo)?login_error=1")
    }
    let name = (claims["name"] as? String) ?? (claims["email"] as? String) ?? "User"
    let email = claims["email"] as? String

    // Server-side verified roles, not a local unverified decode - see design.md's "Server-side
    // JWKS verification" decision. A users-api outage fails the login rather than granting an
    // unverified session; that's the correct failure mode for the suite's sole session writer.
    let authz: UsersAPIClient.AuthzCheckResponse
    do {
      authz = try await req.usersAPI.checkAuthz(accessToken: tokenResponse.accessToken)
    } catch {
      req.logger.error("users-api /authz/check call failed: \(error)")
      return req.redirect(to: "\(returnTo)?login_error=1")
    }
    guard authz.allowed, authz.sub == sub || authz.sub == nil else {
      req.logger.warning("users-api denied or mismatched authz check for sub \(sub)")
      return req.redirect(to: "\(returnTo)?login_error=1")
    }

    req.currentUser = SessionUser(sub: sub, name: name, email: email, roles: authz.roles ?? [])
    return req.redirect(to: returnTo)
  }

  @Sendable
  func logout(req: Request) async throws -> Response {
    let config = req.application.auth0Config
    req.currentUser = nil
    req.session.destroy()
    return config.isConfigured
      ? req.redirect(to: config.logoutURL) : req.redirect(to: "/")
  }
}
