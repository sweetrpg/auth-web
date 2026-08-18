import Vapor

struct Auth0Config {
  let domain: String
  let clientID: String
  let clientSecret: String
  let callbackURL: String
  let audience: String?

  var isConfigured: Bool { !domain.isEmpty && !clientID.isEmpty }

  static func fromEnvironment() -> Auth0Config {
    Auth0Config(
      domain: Environment.get("AUTH0_DOMAIN") ?? "",
      clientID: Environment.get("AUTH0_CLIENT_ID") ?? "",
      clientSecret: Environment.get("AUTH0_CLIENT_SECRET") ?? "",
      callbackURL: Environment.get("AUTH0_CALLBACK_URL") ?? "http://localhost:8080/auth/callback",
      audience: Environment.get("AUTH0_AUDIENCE")
    )
  }

  /// Unreserved characters per RFC 3986 - the only characters guaranteed to survive unescaped.
  /// `URLComponents.queryItems`' own percent-encoding is too lenient for this: it leaves `+`
  /// unescaped since `+` is a legal, non-reserved query character per RFC 3986, but Vapor (like
  /// most web frameworks) decodes query values as `application/x-www-form-urlencoded`, where an
  /// unescaped `+` means a literal space. A base64 `state` value containing `+` would round-trip
  /// through Auth0's redirect back to `/auth/callback` and get silently corrupted (`+` -> ` `)
  /// on decode, no longer matching the session-stored pending-login key - producing
  /// `login_error=expired` for a perfectly legitimate login. Percent-encoding every value with
  /// this stricter set (also used by `logoutURL`, where the same leniency would let a nested
  /// URL's own `?`/`=` be misread as part of the outer query string) avoids both problems.
  private static let unreservedCharacters = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

  /// Builds a `URLComponents`' `percentEncodedQuery` from name/value pairs, each value escaped
  /// with `unreservedCharacters` rather than `URLComponents.queryItems`' own (too lenient)
  /// encoding - the query-item builder API without its unsafe-for-us default encoding.
  private static func percentEncodedQuery(_ items: [(name: String, value: String)]) -> String {
    items.map { item in
      let encoded = item.value.addingPercentEncoding(withAllowedCharacters: unreservedCharacters)
      return "\(item.name)=\(encoded ?? item.value)"
    }.joined(separator: "&")
  }

  func authorizeURL(state: String) -> String {
    var components = URLComponents(string: "https://\(domain)/authorize")!
    var items: [(name: String, value: String)] = [
      ("response_type", "code"),
      ("client_id", clientID),
      ("redirect_uri", callbackURL),
      ("scope", "openid profile email"),
      ("state", state),
    ]
    if let audience { items.append(("audience", audience)) }
    components.percentEncodedQuery = Self.percentEncodedQuery(items)
    return components.url!.absoluteString
  }

  /// Auth0 only allows a `returnTo` that exactly matches a registered Allowed Logout URL, so the
  /// visitor's actual (arbitrary) destination can't be passed straight through - it travels as
  /// `return_to` on this app's own fixed `/auth/logout-complete` URL instead, which is what gets
  /// registered with Auth0. See design.md's "Add a second local route" decision.
  func logoutURL(returnTo: String) -> String {
    let logoutCompleteBase = callbackURL.replacingOccurrences(
      of: "/auth/callback", with: "/auth/logout-complete")
    let returnToQuery = Self.percentEncodedQuery([("return_to", returnTo)])
    let logoutCompleteURL = "\(logoutCompleteBase)?\(returnToQuery)"

    var components = URLComponents(string: "https://\(domain)/v2/logout")!
    components.percentEncodedQuery = Self.percentEncodedQuery([
      ("client_id", clientID), ("returnTo", logoutCompleteURL),
    ])
    return components.url!.absoluteString
  }
}

extension Application {
  private struct Auth0ConfigKey: StorageKey {
    typealias Value = Auth0Config
  }

  var auth0Config: Auth0Config {
    get {
      guard let config = storage[Auth0ConfigKey.self] else {
        let config = Auth0Config.fromEnvironment()
        storage[Auth0ConfigKey.self] = config
        return config
      }
      return config
    }
    set { storage[Auth0ConfigKey.self] = newValue }
  }
}
