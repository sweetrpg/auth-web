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

  /// A small, closed set of user-safe categories for a failed login - never the raw Auth0/
  /// `users-api` error text, which could leak internal detail (stack traces, upstream error
  /// messages) into a URL query parameter and from there into browser history/referrer headers/
  /// server logs downstream. Each consuming frontend maps these to its own copy; see
  /// `main-web`'s `routes/main.rs`.
  private enum LoginErrorReason: String {
    /// Auth0 itself returned an `error` param - most commonly the visitor cancelled/declined
    /// consent at Auth0's login screen.
    case denied
    /// Missing `code` or a `state` mismatch - the flow's session expired, was replayed (e.g. a
    /// stale back-button navigation to `/auth/callback`), or never had a valid `state` to begin
    /// with.
    case expired
    /// Everything downstream of a valid Auth0 code that isn't `forbidden`: the token exchange,
    /// ID token decode, or `users-api`'s `/authz/check` call itself failed. Grouped together
    /// because from the visitor's side these are all "something on our end broke," not
    /// something they can fix by trying differently.
    case unavailable
    /// `users-api` completed the check but denied access, or returned a `sub` that doesn't
    /// match the token just verified - a real, non-transient "you don't have access" outcome,
    /// distinct from `unavailable`.
    case forbidden
  }

  private func errorRedirect(_ req: Request, to returnTo: String, reason: LoginErrorReason)
    -> Response
  {
    req.redirect(to: "\(returnTo)?login_error=\(reason.rawValue)")
  }

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
      return errorRedirect(req, to: returnTo, reason: .denied)
    }
    guard let code = query.code, query.state == req.session.data["auth_state"] else {
      req.logger.warning("Auth0 callback missing code or state mismatch")
      return errorRedirect(req, to: returnTo, reason: .expired)
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
      return errorRedirect(req, to: returnTo, reason: .unavailable)
    }
    let name = (claims["name"] as? String) ?? (claims["email"] as? String) ?? "User"
    let email = claims["email"] as? String

    // Server-side verified roles, not a local unverified decode - see design.md's "Server-side
    // JWKS verification" decision. An auth-api outage fails the login rather than granting an
    // unverified session; that's the correct failure mode for the suite's sole session writer.
    let authz: AuthAPIClient.AuthzCheckResponse
    do {
      authz = try await req.authAPI.checkAuthz(accessToken: tokenResponse.accessToken)
    } catch {
      req.logger.error("auth-api /authz/check call failed: \(error)")
      return errorRedirect(req, to: returnTo, reason: .unavailable)
    }
    guard authz.allowed, authz.sub == sub || authz.sub == nil else {
      req.logger.warning("auth-api denied or mismatched authz check for sub \(sub)")
      return errorRedirect(req, to: returnTo, reason: .forbidden)
    }

    req.currentUser = SessionUser(
      sub: sub, name: name, email: email, roles: authz.roles ?? [],
      accessToken: tokenResponse.accessToken)
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
