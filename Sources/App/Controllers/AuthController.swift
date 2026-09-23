import Vapor

/// Fallback access-token lifetime when Auth0 omits `expires_in`: 24 hours, matching Auth0's
/// typical access-token lifetime (confirm against the tenant's actual dashboard setting). This
/// bounds only the token stored in `SessionUser.expiry` - the session record itself lives under
/// `ResilientRedisSessionDriver`'s idle/absolute expiry policy and is unrelated.
private let fallbackTokenLifetime: TimeInterval = 60 * 60 * 24

/// Sole implementer of the Auth0 Authorization Code flow for the whole suite - see design.md's
/// "auth-web is the sole owner of the Authorization Code exchange" decision in platform's
/// add-user-api-authn-authz change. Every other frontend's "log in" link points at
/// `/auth/login?return_to=<path>` here instead of running its own redirect/callback.
struct AuthController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("auth", "login", use: redirectToAuth0)
    routes.get("auth", "callback", use: callback)
    routes.post("auth", "logout", use: logout)
    routes.get("auth", "logout-complete", use: logoutComplete)
    // Auth0 RP-initiated login: when the tenant's "Initiate Login URI" points at this host's
    // bare `/login` (or isn't set to `/auth/login`), Auth0 bounces the visitor there with an
    // `?iss=` param instead of rendering its Universal Login form. Alias it to the same
    // handler so that round trip completes instead of 404ing. `redirectToAuth0` ignores the
    // extra `iss` param and, with no `return_to`, sends the user back to `/` after login. The
    // long-term fix is to set the Auth0 Application's Initiate Login URI to `/auth/login`.
    routes.get("login", use: redirectToAuth0)

    // Account linking: attaches a second Auth0 identity to the currently signed-in session's
    // User.id without ending that session - see sweetrpg/platform's link-user-accounts design.md.
    routes.get("auth", "link", "start", use: linkStart)
    routes.get("auth", "link", "callback", use: linkCallback)
  }

  /// Keys a pending login's `return_to` by its own `state` value rather than a single shared
  /// session slot, so two `/auth/login` calls in the same session (a browser link-prefetch/
  /// hover-preload racing a real click, a double form submission, ...) don't clobber each
  /// other's pending state - each Auth0 round trip only ever needs to find its own entry. See
  /// `openspec/changes/auth-web-logout-preserve-return-path`'s follow-up in
  /// `sweetrpg/platform` for how the previous single-slot design produced `login_error=expired`
  /// under exactly this race.
  private static func pendingLoginKey(state: String) -> String { "auth_pending_\(state)" }

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
    struct LoginQuery: Content {
      let returnTo: String?
      enum CodingKeys: String, CodingKey { case returnTo = "return_to" }
    }
    let query = try req.query.decode(LoginQuery.self)

    let state = [UInt8].random(count: 16).base64String()
    req.session.data[Self.pendingLoginKey(state: state)] = sanitizedReturnTo(query.returnTo)
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
    // Looks up (and consumes) the pending login this `state` was issued for - `pendingReturnTo`
    // being non-nil is what used to be a direct `state == storedState` comparison against a
    // single shared session slot; keying per-state instead means a second, unrelated
    // `/auth/login` call in this session can't invalidate this one's pending state.
    let pendingKey = query.state.map(Self.pendingLoginKey(state:))
    let pendingReturnTo = pendingKey.flatMap { req.session.data[$0] }
    if let pendingKey { req.session.data[pendingKey] = nil }
    let returnTo = pendingReturnTo ?? "/"

    if let error = query.error {
      req.logger.warning("Auth0 callback returned an error: \(error)")
      return errorRedirect(req, to: returnTo, reason: .denied)
    }
    guard let code = query.code, pendingReturnTo != nil else {
      req.logger.warning("Auth0 callback missing code or no matching pending login for state")
      return errorRedirect(req, to: returnTo, reason: .expired)
    }

    let config = req.application.auth0Config
    struct TokenResponse: Content {
      let accessToken: String
      let idToken: String
      /// Seconds until the access token expires, per Auth0's token response - drives this
      /// session's `expiry` (see `SessionUser.expiry`). Falls back to `fallbackTokenLifetime`
      /// if Auth0 omits it, so a session always has a bound rather than living forever.
      let expiresIn: Int?

      enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
      }
    }
    // Auth0 returning a non-token body (an error JSON, an outage page, ...) must not crash this
    // request uncaught - a visitor whose code has already expired or been replayed is a routine,
    // expected failure mode, not a 500.
    let tokenResponse: TokenResponse
    do {
      tokenResponse = try await req.client.post(
        URI(string: "https://\(config.domain)/oauth/token"),
        content: [
          "grant_type": "authorization_code",
          "client_id": config.clientID,
          "client_secret": config.clientSecret,
          "code": code,
          "redirect_uri": config.callbackURL,
        ] as [String: String]
      ).content.decode(TokenResponse.self)
    } catch {
      req.logger.error("Auth0 token exchange failed: \(error)")
      return errorRedirect(req, to: returnTo, reason: .unavailable)
    }

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

    let userID = await Self.provisionedUserID(
      req: req, accessToken: tokenResponse.accessToken, name: name, email: email)

    let ttl = tokenResponse.expiresIn.map(TimeInterval.init) ?? fallbackTokenLifetime
    req.currentUser = SessionUser(
      sub: sub, name: name, email: email, roles: authz.roles ?? [],
      accessToken: tokenResponse.accessToken, expiry: Date().addingTimeInterval(ttl),
      userID: userID)
    return req.redirect(to: returnTo)
  }

  /// Calls `users-api`'s find-or-create provisioning path and returns the resulting `User.id`,
  /// or `nil` if the call fails - a provisioning outage degrades this login to a session
  /// without a `User.id` rather than blocking it (see design.md's "Failure mode" decision).
  /// A separate method (rather than inlined in `callback`) so this degrade-on-failure behavior
  /// is directly unit-testable without also stubbing the Auth0 token exchange it normally
  /// follows.
  static func provisionedUserID(req: Request, accessToken: String, name: String, email: String?)
    async -> String?
  {
    do {
      return try await req.usersAPI.provision(accessToken: accessToken, name: name, email: email)
        .userId
    } catch {
      req.logger.warning("users-api provisioning call failed: \(error)")
      return nil
    }
  }

  @Sendable
  func logout(req: Request) async throws -> Response {
    struct LogoutQuery: Content {
      let returnTo: String?
      enum CodingKeys: String, CodingKey { case returnTo = "return_to" }
    }
    let query = try req.query.decode(LogoutQuery.self)
    let returnTo = sanitizedReturnTo(query.returnTo)

    let config = req.application.auth0Config
    req.currentUser = nil
    req.session.destroy()
    return config.isConfigured
      ? req.redirect(to: config.logoutURL(returnTo: returnTo)) : req.redirect(to: returnTo)
  }

  /// Auth0's own `returnTo` is pinned to this fixed URL (see `Auth0Config.logoutURL`) since it
  /// can't be pre-registered for every possible destination - this route performs the actual
  /// redirect to the visitor's destination once Auth0's logout round trip completes.
  @Sendable
  func logoutComplete(req: Request) async throws -> Response {
    struct LogoutCompleteQuery: Content {
      let returnTo: String?
      enum CodingKeys: String, CodingKey { case returnTo = "return_to" }
    }
    let query = try req.query.decode(LogoutCompleteQuery.self)
    return req.redirect(to: sanitizedReturnTo(query.returnTo))
  }

  /// A small, closed set of user-safe categories for a failed link attempt - same reasoning as
  /// `LoginErrorReason`, plus `.conflict` for the one outcome the caller needs to distinguish
  /// from a generic failure (see design.md's "Conflict rule: reject, never merge").
  private enum LinkErrorReason: String {
    case denied
    case expired
    case unavailable
    case conflict
  }

  private func linkErrorRedirect(_ req: Request, to returnTo: String, reason: LinkErrorReason)
    -> Response
  {
    req.redirect(to: "\(returnTo)?link_error=\(reason.rawValue)")
  }

  /// Keyed by the link ticket itself (used as Auth0's `state`) rather than a separate locally
  /// generated value - `users-api` already mints this ticket as a single-use, signed credential
  /// scoped to the linking session's `User.id` (see design.md), so reusing it as `state` needs no
  /// second value to keep in sync. Kept in its own session key namespace (`auth_link_pending_*`)
  /// distinct from `pendingLoginKey` so an in-flight login and an in-flight link never collide.
  private static func pendingLinkKey(state: String) -> String { "auth_link_pending_\(state)" }

  /// Starts the account-linking round trip for the currently signed-in session. Requires an
  /// active session (401 otherwise - this is an action a signed-in visitor takes from an
  /// account-settings page, not a page of its own to redirect through) and a provisioned
  /// `User.id` to attach the second identity to. Never touches the original session.
  ///
  /// Forwards the session's own Auth0 access token to `users-api`'s link/start call rather than
  /// sending a `User.id` in the request body - `users-api` resolves the account to link against
  /// from that verified token's own subject server-side (see `UsersAPIClient.linkStart`'s doc
  /// comment for why). The local `user.userID != nil` check below is only a cheap pre-flight
  /// short-circuit (avoids a network round trip for a session that never provisioned an account
  /// in the first place); `users-api` remains the actual source of truth for whether an account
  /// exists to link against.
  @Sendable
  func linkStart(req: Request) async throws -> Response {
    guard let user = req.currentUser else {
      throw Abort(.unauthorized, reason: "An active session is required to link another identity")
    }
    guard user.userID != nil else {
      throw Abort(.unprocessableEntity, reason: "This session has no account to link against")
    }
    let config = req.application.auth0Config
    guard config.isConfigured else {
      req.logger.warning("AUTH0_DOMAIN/AUTH0_CLIENT_ID not set - cannot start link flow")
      throw Abort(.serviceUnavailable, reason: "Login is not configured")
    }
    struct LinkStartQuery: Content {
      let returnTo: String?
      enum CodingKeys: String, CodingKey { case returnTo = "return_to" }
    }
    let query = try req.query.decode(LinkStartQuery.self)

    let ticket: String
    do {
      ticket = try await req.usersAPI.linkStart(accessToken: user.accessToken).ticket
    } catch {
      req.logger.error("users-api link/start call failed: \(error)")
      throw Abort(.serviceUnavailable, reason: "Could not start account linking")
    }

    req.session.data[Self.pendingLinkKey(state: ticket)] = sanitizedReturnTo(query.returnTo)
    return req.redirect(
      to: config.authorizeURL(state: ticket, redirectURI: config.linkCallbackURL))
  }

  /// Completes the account-linking round trip. Exchanges Auth0's code for the second identity's
  /// token, forwards the ticket (carried through as `state`) and that token to `users-api`, and
  /// redirects back into the app - success or conflict - without ever reading or writing the
  /// original session's `currentUser`.
  @Sendable
  func linkCallback(req: Request) async throws -> Response {
    struct CallbackQuery: Content {
      let code: String?
      let state: String?
      let error: String?
    }
    let query = try req.query.decode(CallbackQuery.self)
    let pendingKey = query.state.map(Self.pendingLinkKey(state:))
    let pendingReturnTo = pendingKey.flatMap { req.session.data[$0] }
    if let pendingKey { req.session.data[pendingKey] = nil }
    let returnTo = pendingReturnTo ?? "/"

    if let error = query.error {
      req.logger.warning("Auth0 link callback returned an error: \(error)")
      return linkErrorRedirect(req, to: returnTo, reason: .denied)
    }
    guard let code = query.code, let ticket = query.state, pendingReturnTo != nil else {
      req.logger.warning("Auth0 link callback missing code or no matching pending link for state")
      return linkErrorRedirect(req, to: returnTo, reason: .expired)
    }

    let config = req.application.auth0Config
    struct TokenResponse: Content {
      let accessToken: String
      enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
    }
    let tokenResponse: TokenResponse
    do {
      tokenResponse = try await req.client.post(
        URI(string: "https://\(config.domain)/oauth/token"),
        content: [
          "grant_type": "authorization_code",
          "client_id": config.clientID,
          "client_secret": config.clientSecret,
          "code": code,
          "redirect_uri": config.linkCallbackURL,
        ] as [String: String]
      ).content.decode(TokenResponse.self)
    } catch {
      req.logger.error("Auth0 link token exchange failed: \(error)")
      return linkErrorRedirect(req, to: returnTo, reason: .unavailable)
    }

    do {
      _ = try await req.usersAPI.linkComplete(ticket: ticket, accessToken: tokenResponse.accessToken)
    } catch is UsersAPIClient.LinkConflictError {
      return linkErrorRedirect(req, to: returnTo, reason: .conflict)
    } catch {
      req.logger.error("users-api link/complete call failed: \(error)")
      return linkErrorRedirect(req, to: returnTo, reason: .unavailable)
    }

    return req.redirect(to: returnTo)
  }
}
