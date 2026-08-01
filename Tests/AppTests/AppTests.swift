import Testing
import VaporTesting

@testable import App

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
        #expect(res.headers.first(name: .location)?.contains("login_error=1") == true)
      }
    }
  }
}
