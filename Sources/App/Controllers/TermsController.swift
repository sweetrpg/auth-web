import Vapor

/// A login held back until the user accepts the current terms. Lives in the session under its own
/// key, never under the shared `user` key, so no other frontend sees a usable session until the
/// user accepts.
private struct PendingTermsLogin: Codable {
  let user: SessionUser
  let returnTo: String
  let version: String
}

/// Post-login terms acceptance - see `sweetrpg/platform`'s `publish-terms-of-service` change.
/// Everything here is inert unless the `terms-acceptance-gate` flag is on and
/// `REQUIRED_TERMS_VERSION` is set.
struct TermsController: RouteCollection {
  static let flagKey = "terms-acceptance-gate"
  private static let pendingKey = "auth_terms_pending"
  private static let csrfKey = "auth_terms_csrf"

  func boot(routes: RoutesBuilder) throws {
    routes.get("auth", "terms", use: show)
    routes.post("auth", "terms", use: accept)
    routes.post("auth", "terms", "decline", use: decline)
    routes.get("auth", "terms", "declined", use: declined)
  }

  /// Called by the Auth0 callback once the user is verified and provisioned. Returns a redirect
  /// to the accept page when the user must accept first, or `nil` to let login complete. Every
  /// failure here fails open: a flag or `users-api` outage must not lock users out.
  static func holdLoginIfNeeded(req: Request, user: SessionUser, returnTo: String) async
    -> Response?
  {
    guard let policy = req.application.termsPolicy else { return nil }
    guard
      await req.application.featureFlags.isEnabled(flagKey, default: false, on: req.client)
    else { return nil }
    let accepted: TermsAcceptance?
    do {
      accepted = try await req.application.termsStore.fetch(
        accessToken: user.accessToken, on: req.client)
    } catch {
      req.logger.error("users-api terms acceptance lookup failed, letting user in: \(error)")
      return nil
    }
    guard policy.needsAcceptance(accepted) else { return nil }
    guard
      let data = try? JSONEncoder.iso8601.encode(
        PendingTermsLogin(user: user, returnTo: returnTo, version: policy.requiredVersion)),
      let json = String(data: data, encoding: .utf8)
    else { return nil }
    req.session.data[pendingKey] = json
    req.session.data[csrfKey] = [UInt8].random(count: 16).base64String()
    return req.redirect(to: "/auth/terms")
  }

  private func pending(_ req: Request) -> PendingTermsLogin? {
    req.session.data[Self.pendingKey]
      .flatMap { $0.data(using: .utf8) }
      .flatMap { try? JSONDecoder.iso8601.decode(PendingTermsLogin.self, from: $0) }
  }

  private func html(_ body: String, status: HTTPResponseStatus = .ok) -> Response {
    var headers = HTTPHeaders()
    headers.contentType = .html
    return Response(status: status, headers: headers, body: .init(string: body))
  }

  private func validCSRF(_ req: Request, submitted: String?) -> Bool {
    guard let expected = req.session.data[Self.csrfKey], let submitted else { return false }
    return expected == submitted
  }

  @Sendable
  func show(req: Request) async throws -> Response {
    guard pending(req) != nil, let csrf = req.session.data[Self.csrfKey] else {
      return req.redirect(to: "/")
    }
    return html(
      TermsPage.renderAccept(
        csrf: csrf, errorKey: nil, l10n: req.l10n, footer: req.siteFooterHTML,
        sharedURL: req.sharedURL))
  }

  private struct Form: Content {
    let csrf: String?
    let accept: String?
  }

  @Sendable
  func accept(req: Request) async throws -> Response {
    guard let held = pending(req) else { return req.redirect(to: "/") }
    let form = try req.content.decode(Form.self)
    guard validCSRF(req, submitted: form.csrf), let csrf = form.csrf else {
      throw Abort(.forbidden)
    }
    guard form.accept == "yes" else {
      return html(
        TermsPage.renderAccept(
          csrf: csrf, errorKey: "terms.error_unchecked", l10n: req.l10n,
          footer: req.siteFooterHTML, sharedURL: req.sharedURL),
        status: .unprocessableEntity)
    }
    do {
      try await req.application.termsStore.record(
        version: held.version, accessToken: held.user.accessToken, on: req.client)
    } catch {
      req.logger.error("users-api terms acceptance write failed: \(error)")
      return html(
        TermsPage.renderAccept(
          csrf: csrf, errorKey: "terms.error_record_failed", l10n: req.l10n,
          footer: req.siteFooterHTML, sharedURL: req.sharedURL),
        status: .serviceUnavailable)
    }
    req.session.data[Self.pendingKey] = nil
    req.session.data[Self.csrfKey] = nil
    req.currentUser = held.user
    return req.redirect(to: held.returnTo)
  }

  @Sendable
  func decline(req: Request) async throws -> Response {
    let form = try req.content.decode(Form.self)
    guard validCSRF(req, submitted: form.csrf) else { throw Abort(.forbidden) }
    let config = req.application.auth0Config
    req.currentUser = nil
    req.session.destroy()
    let declinedPath = "/auth/terms/declined"
    return config.isConfigured
      ? req.redirect(to: config.logoutURL(returnTo: declinedPath)) : req.redirect(to: declinedPath)
  }

  @Sendable
  func declined(req: Request) async throws -> Response {
    html(
      TermsPage.renderDeclined(
        l10n: req.l10n, footer: req.siteFooterHTML, sharedURL: req.sharedURL))
  }
}

extension JSONEncoder {
  fileprivate static var iso8601: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}

extension JSONDecoder {
  fileprivate static var iso8601: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
