import Foundation
import Testing
import VaporTesting

@testable import App

private struct FakeFlags: FeatureFlagEvaluating {
  let enabled: Bool
  func isEnabled(_ key: String, default defaultValue: Bool, on client: Client) async -> Bool {
    enabled
  }
}

private final class FakeTermsStore: TermsStoring, @unchecked Sendable {
  private let lock = NSLock()
  private let accepted: TermsAcceptance?
  private let fetchFails: Bool
  private var recorded: [String] = []

  init(accepted: TermsAcceptance?, fetchFails: Bool = false) {
    self.accepted = accepted
    self.fetchFails = fetchFails
  }

  var recordedVersions: [String] {
    lock.withLock { recorded }
  }

  func fetch(accessToken: String, on client: Client) async throws -> TermsAcceptance? {
    if fetchFails { throw Abort(.serviceUnavailable) }
    return accepted
  }

  func record(version: String, accessToken: String, on client: Client) async throws {
    lock.withLock { recorded.append(version) }
  }
}

private func acceptance(_ version: String) -> TermsAcceptance {
  TermsAcceptance(version: version, acceptedAt: "2026-10-01T00:00:00Z")
}

/// Registers `/test-login`, which runs the same hook the Auth0 callback runs after a verified
/// login: either a redirect to the accept page, or a usable session.
private func installLoginRoute(_ app: Application) {
  app.get("test-login") { req async throws -> Response in
    let user = SessionUser(
      sub: "auth0|abc", name: "Ada", email: nil, roles: [], accessToken: "tok",
      expiry: Date().addingTimeInterval(3600), userID: "u1")
    if let hold = await TermsController.holdLoginIfNeeded(
      req: req, user: user, returnTo: "/catalog")
    {
      return hold
    }
    req.currentUser = user
    return req.redirect(to: "/catalog")
  }
  app.get("test-whoami") { req -> String in req.currentUser?.sub ?? "nobody" }
}

private func sessionCookie(_ res: TestingHTTPResponse) -> String {
  String(res.headers.first(name: .setCookie)?.split(separator: ";").first ?? "")
}

private func configured(
  accepted: TermsAcceptance?, fetchFails: Bool = false, flag: Bool = true,
  required: String = "2.0", material: Bool = true,
  _ body: (Application, FakeTermsStore) async throws -> Void
) async throws {
  try await withApp(configure: configure) { app in
    let store = FakeTermsStore(accepted: accepted, fetchFails: fetchFails)
    app.termsStore = store
    app.featureFlags = FakeFlags(enabled: flag)
    app.termsPolicy = try TermsPolicy(requiredVersion: required, isMaterial: material)
    installLoginRoute(app)
    try await body(app, store)
  }
}

@Suite("TermsPolicy")
struct TermsPolicyTests {
  @Test("no record needs acceptance, material or not")
  func missingRecord() throws {
    #expect(try TermsPolicy(requiredVersion: "1.0", isMaterial: false).needsAcceptance(nil))
    #expect(try TermsPolicy(requiredVersion: "1.0", isMaterial: true).needsAcceptance(nil))
  }

  @Test("older version needs acceptance only when material")
  func olderVersion() throws {
    let old = acceptance("1.0")
    #expect(try TermsPolicy(requiredVersion: "2.0", isMaterial: true).needsAcceptance(old))
    #expect(try !TermsPolicy(requiredVersion: "2.0", isMaterial: false).needsAcceptance(old))
  }

  @Test("current or newer version does not need acceptance; 1 equals 1.0")
  func currentVersion() throws {
    let policy = try TermsPolicy(requiredVersion: "1.0", isMaterial: true)
    #expect(!policy.needsAcceptance(acceptance("1")))
    #expect(!policy.needsAcceptance(acceptance("1.1")))
  }

  @Test("versions compare numerically, not lexically")
  func numericCompare() throws {
    #expect(TermsVersion("1.10")! > TermsVersion("1.9")!)
  }

  @Test("a malformed required version is rejected")
  func malformedVersion() {
    #expect(throws: TermsPolicy.ConfigError.self) {
      try TermsPolicy(requiredVersion: "v2", isMaterial: true)
    }
  }
}

@Suite("Terms acceptance gate")
struct TermsGateTests {
  @Test("no record sends the user to the accept page and withholds the session")
  func noRecord() async throws {
    try await configured(accepted: nil) { app, _ in
      var cookie = ""
      try await app.testing().test(.GET, "test-login") { res in
        #expect(res.status == .seeOther)
        #expect(res.headers.first(name: .location) == "/auth/terms")
        cookie = sessionCookie(res)
      }
      try await app.testing().test(
        .GET, "test-whoami", headers: HTTPHeaders([("Cookie", cookie)])
      ) {
        #expect($0.body.string == "nobody")
      }
    }
  }

  @Test("older version sends the user to the page when material")
  func olderMaterial() async throws {
    try await configured(accepted: acceptance("1.0"), material: true) { app, _ in
      try await app.testing().test(.GET, "test-login") { res in
        #expect(res.headers.first(name: .location) == "/auth/terms")
      }
    }
  }

  @Test("older version does not when not material")
  func olderNotMaterial() async throws {
    try await configured(accepted: acceptance("1.0"), material: false) { app, _ in
      try await app.testing().test(.GET, "test-login") { res in
        #expect(res.headers.first(name: .location) == "/catalog")
      }
    }
  }

  @Test("flag off never redirects, even with no record")
  func flagOff() async throws {
    try await configured(accepted: nil, flag: false) { app, _ in
      try await app.testing().test(.GET, "test-login") { res in
        #expect(res.headers.first(name: .location) == "/catalog")
      }
    }
  }

  @Test("users-api down lets the user in")
  func usersAPIDown() async throws {
    try await configured(accepted: nil, fetchFails: true) { app, _ in
      try await app.testing().test(.GET, "test-login") { res in
        #expect(res.headers.first(name: .location) == "/catalog")
      }
    }
  }

  @Test("accepting records the required version and completes login")
  func accepting() async throws {
    try await configured(accepted: nil) { app, store in
      var cookie = ""
      try await app.testing().test(.GET, "test-login") { cookie = sessionCookie($0) }
      let headers = HTTPHeaders([("Cookie", cookie)])

      var csrf = ""
      try await app.testing().test(.GET, "auth/terms", headers: headers) { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("href=\"/terms\""))
        #expect(res.body.string.contains("href=\"/privacy\""))
        #expect(!res.body.string.contains("checked"))
        let marker = "name=\"csrf\" value=\""
        let tail = res.body.string.components(separatedBy: marker)[1]
        csrf = String(tail.prefix(while: { $0 != "\"" }))
      }

      var body = ByteBuffer(
        string: "csrf=\(csrf.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)")
      try await app.testing().test(
        .POST, "auth/terms",
        headers: HTTPHeaders([
          ("Cookie", cookie), ("Content-Type", "application/x-www-form-urlencoded"),
        ]),
        body: body
      ) { res in
        #expect(res.status == .unprocessableEntity)
      }
      #expect(store.recordedVersions.isEmpty)

      body = ByteBuffer(
        string:
          "csrf=\(csrf.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)&accept=yes")
      try await app.testing().test(
        .POST, "auth/terms",
        headers: HTTPHeaders([
          ("Cookie", cookie), ("Content-Type", "application/x-www-form-urlencoded"),
        ]),
        body: body
      ) { res in
        #expect(res.status == .seeOther)
        #expect(res.headers.first(name: .location) == "/catalog")
      }
      #expect(store.recordedVersions == ["2.0"])
      try await app.testing().test(.GET, "test-whoami", headers: headers) {
        #expect($0.body.string == "auth0|abc")
      }
    }
  }

  @Test("declining ends the session without ever creating a usable one")
  func declining() async throws {
    try await configured(accepted: nil) { app, store in
      var cookie = ""
      try await app.testing().test(.GET, "test-login") { cookie = sessionCookie($0) }
      let headers = HTTPHeaders([("Cookie", cookie)])
      var csrf = ""
      try await app.testing().test(.GET, "auth/terms", headers: headers) { res in
        let tail = res.body.string.components(separatedBy: "name=\"csrf\" value=\"")[1]
        csrf = String(tail.prefix(while: { $0 != "\"" }))
      }
      try await app.testing().test(
        .POST, "auth/terms/decline",
        headers: HTTPHeaders([
          ("Cookie", cookie), ("Content-Type", "application/x-www-form-urlencoded"),
        ]),
        body: ByteBuffer(
          string: "csrf=\(csrf.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)")
      ) { res in
        #expect(res.status == .seeOther)
        #expect(res.headers.first(name: .location) == "/auth/terms/declined")
      }
      #expect(store.recordedVersions.isEmpty)
      try await app.testing().test(.GET, "test-whoami", headers: headers) {
        #expect($0.body.string == "nobody")
      }
      try await app.testing().test(.GET, "auth/terms/declined") { res in
        #expect(res.status == .ok)
      }
    }
  }
}

@Suite("UsersAPITermsStore wire shapes")
struct UsersAPITermsStoreTests {
  @Test("GET /profile terms_accepted decodes version and accepted_at")
  func decodesRecord() throws {
    let json =
      #"{"name":"Ada","terms_accepted":{"version":"1.0","accepted_at":"2026-11-02T19:10:09.123Z"}}"#
    let profile = try JSONDecoder().decode(
      UsersAPITermsStore.ProfileResponse.self, from: Data(json.utf8))
    #expect(
      profile.termsAccepted
        == TermsAcceptance(version: "1.0", acceptedAt: "2026-11-02T19:10:09.123Z"))
  }

  @Test("a null terms_accepted decodes as no record")
  func decodesNull() throws {
    let profile = try JSONDecoder().decode(
      UsersAPITermsStore.ProfileResponse.self, from: Data(#"{"terms_accepted":null}"#.utf8))
    #expect(profile.termsAccepted == nil)
  }
}
