import AdminAPIClient
import Foundation
import Testing
import VaporTesting

@testable import App

/// Fixed-response `MaintenanceModeChecking` fake - see MaintenanceModeChecking.swift for why
/// production code depends on this protocol instead of `AdminClient` directly.
private struct FakeMaintenanceModeChecker: MaintenanceModeChecking {
  let modes: [MaintenanceMode]
  func fetchMaintenanceModes(scopes: [String]) async -> [MaintenanceMode] { modes }
}

/// `MaintenanceMode` only exposes `Decodable` (no public memberwise init), matching the wire
/// shape it's meant to model - so tests build one the same way production code does: decoding
/// admin-api's JSON.
private func makeMaintenanceMode(
  label: String, description: String, startsAt: String, endsAt: String?
) throws -> MaintenanceMode {
  let json: [String: Any?] = [
    "scope_type": "platform", "scope_value": "", "label": label, "description": description,
    "starts_at": startsAt, "ends_at": endsAt,
  ]
  let data = try JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
  return try JSONDecoder().decode(MaintenanceMode.self, from: data)
}

@Suite("App")
struct AppTests {
  @Test("status ping responds ok")
  func statusPing() async throws {
    try await withApp(configure: configure) { app in
      try await app.testing().test(.GET, "status/ping") { res in
        #expect(res.status == .ok)
      }
    }
  }

  @Test("login without Auth0 configured returns 503")
  func loginUnconfigured() async throws {
    try await withApp(configure: configure) { app in
      try await app.testing().test(.GET, "auth/login") { res in
        #expect(res.status == .serviceUnavailable)
      }
    }
  }

  @Test("callback with mismatched state redirects with an error flag")
  func callbackStateMismatch() async throws {
    try await withApp(configure: configure) { app in
      try await app.testing().test(.GET, "auth/callback?code=abc&state=wrong") { res in
        #expect(res.status == .seeOther)
        #expect(res.headers.first(name: .location)?.contains("login_error=expired") == true)
      }
    }
  }

  @Test("login renders the maintenance page when a maintenance mode is active")
  func loginRendersMaintenancePage() async throws {
    let active = try makeMaintenanceMode(
      label: "Scheduled downtime", description: "We're upgrading the auth database.",
      startsAt: "2026-08-01T00:00:00Z", endsAt: "2026-08-01T02:00:00Z")
    try await withApp(configure: configure) { app in
      app.maintenanceModeChecker = FakeMaintenanceModeChecker(modes: [active])
      try await app.testing().test(.GET, "auth/login") { res in
        #expect(res.status == .serviceUnavailable)
        #expect(res.headers.contentType == .html)
        #expect(res.body.string.contains("Scheduled downtime"))
        #expect(res.body.string.contains("We're upgrading the auth database."))
      }
    }
  }

  @Test("login proceeds normally when no maintenance mode is active")
  func loginProceedsWithoutMaintenance() async throws {
    try await withApp(configure: configure) { app in
      app.maintenanceModeChecker = FakeMaintenanceModeChecker(modes: [])
      try await app.testing().test(.GET, "auth/login") { res in
        // Same 503 as `loginUnconfigured` above, but for the unrelated reason that Auth0 isn't
        // configured in this test app - not because maintenance mode intercepted the request.
        #expect(res.status == .serviceUnavailable)
        #expect(res.headers.contentType != .html)
      }
    }
  }

  @Test("an unreachable admin-api fails open to normal rendering")
  func loginFailsOpenWhenAdminAPIUnreachable() async throws {
    try await withApp(configure: configure) { app in
      // Real AdminClient, deliberately pointed at a port nothing listens on - proves the
      // middleware doesn't add its own failure mode around the SDK's fail-open contract.
      app.maintenanceModeChecker = AdminClient(baseURL: "http://127.0.0.1:1")
      try await app.testing().test(.GET, "auth/login") { res in
        #expect(res.status == .serviceUnavailable)
        #expect(res.headers.contentType != .html)
      }
    }
  }

  @Test("an active maintenance mode does not block the Auth0 callback route")
  func callbackNotGatedByMaintenanceMode() async throws {
    let active = try makeMaintenanceMode(
      label: "Scheduled downtime", description: "We're upgrading the auth database.",
      startsAt: "2026-08-01T00:00:00Z", endsAt: nil)
    try await withApp(configure: configure) { app in
      app.maintenanceModeChecker = FakeMaintenanceModeChecker(modes: [active])
      try await app.testing().test(.GET, "auth/callback?code=abc&state=wrong") { res in
        #expect(res.status == .seeOther)
        #expect(res.headers.first(name: .location)?.contains("login_error=expired") == true)
      }
    }
  }
}
