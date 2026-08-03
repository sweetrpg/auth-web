import Vapor

/// Gates `GET /auth/login` - the only page a visitor lands on to *start* something - behind an
/// active platform or auth-service maintenance-mode record.
///
/// `/auth/callback` is deliberately excluded: this app is the platform's sole Auth0 callback
/// handler (see this repo's AGENTS.md), so blocking it mid-flow would strand a user who already
/// authenticated with Auth0 but hasn't gotten a session back yet. `/auth/logout` and
/// `/status/ping` are excluded too - ending a session, and liveness checks, are both safe (and
/// desirable) to keep working during maintenance.
struct MaintenanceModeMiddleware: AsyncMiddleware {
  private static let gatedPath = "/auth/login"

  func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
    guard req.url.path == Self.gatedPath else {
      return try await next.respond(to: req)
    }

    let modes = await req.application.maintenanceModeChecker.fetchMaintenanceModes(
      scopes: ["platform", "service:auth"])
    guard let active = modes.first else {
      return try await next.respond(to: req)
    }

    let response = Response(status: .serviceUnavailable)
    response.headers.contentType = .html
    response.body = .init(string: MaintenancePage.render(active))
    return response
  }
}
