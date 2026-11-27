import Foundation
import Testing
import VaporTesting

@testable import App

@Suite("Logout and return paths")
struct LogoutReturnTests {
  /// Honoring the page the first user logged out from sends a signed-out browser straight back to
  /// it, and a gated page then bounces the *next* user's login there too.
  @Test(
    "logout never carries the previous user's page",
    arguments: ["%2Fadmin%2F", "%2Fcatalog%2Fbrowse"])
  func logoutIgnoresReturnPath(returnTo: String) async throws {
    try await withApp(configure: configure) { app in
      try await app.testing().test(.POST, "auth/logout?return_to=\(returnTo)") { res in
        #expect(res.headers.first(name: .location) == "/")
      }
    }
  }

  @Test("a signed-out deep link still returns there after login")
  func deepLinkIsKept() async throws {
    try await expectPostLoginLocation(returnTo: "%2Fadmin%2F", startsWith: "/admin/?")
  }

  /// Browsers read `\` as `/` and drop tabs and newlines, so these all leave the site.
  @Test(
    "return_to values a browser treats as another host fall back to the root",
    arguments: [
      "%2F%5Cevil.example", "%2F%09%2Fevil.example", "%2F%0A%2Fevil.example",
      "%2F%2Fevil.example", "https%3A%2F%2Fevil.example",
    ])
  func unsafeReturnPathsAreDropped(returnTo: String) async throws {
    try await expectPostLoginLocation(returnTo: returnTo, startsWith: "/?")
  }

  /// Auth0 is unreachable, so the token exchange fails - but the error redirect still targets
  /// whatever `return_to` the login step stored.
  private func expectPostLoginLocation(returnTo: String, startsWith prefix: String) async throws {
    try await withApp(configure: configure) { app in
      app.auth0Config = Auth0Config(
        domain: "127.0.0.1:1", clientID: "client-id", clientSecret: "secret",
        callbackURL: "http://localhost/auth/callback", audience: nil)
      var cookie = ""
      var state = ""
      try await app.testing().test(.GET, "auth/login?return_to=\(returnTo)") { res in
        cookie = String(res.headers.first(name: .setCookie)?.split(separator: ";").first ?? "")
        state =
          URLComponents(string: res.headers.first(name: .location) ?? "")?.queryItems?
          .first(where: { $0.name == "state" })?.value ?? ""
      }
      let encodedState = try #require(
        state.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
      try await app.testing().test(
        .GET, "auth/callback?code=abc&state=\(encodedState)", headers: ["Cookie": cookie]
      ) { res in
        let location = res.headers.first(name: .location) ?? ""
        #expect(location.hasPrefix(prefix), "got \(location)")
      }
    }
  }
}
