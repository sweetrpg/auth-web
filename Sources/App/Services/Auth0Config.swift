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

  func authorizeURL(state: String) -> String {
    var components = URLComponents(string: "https://\(domain)/authorize")!
    var items = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: callbackURL),
      URLQueryItem(name: "scope", value: "openid profile email"),
      URLQueryItem(name: "state", value: state),
    ]
    if let audience { items.append(URLQueryItem(name: "audience", value: audience)) }
    components.queryItems = items
    return components.url!.absoluteString
  }

  /// Unreserved characters per RFC 3986 - the only characters guaranteed to survive unescaped
  /// when a full URL (itself containing `?`/`=`/`&`) is embedded as a single query parameter
  /// value. `URLComponents.queryItems`' own percent-encoding is too lenient for this (it leaves
  /// `/`, `:`, and `?` unescaped), which would let the nested URL's own `?`/`=` be misread as
  /// part of the outer query string.
  private static let unreservedCharacters = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

  /// Auth0 only allows a `returnTo` that exactly matches a registered Allowed Logout URL, so the
  /// visitor's actual (arbitrary) destination can't be passed straight through - it travels as
  /// `return_to` on this app's own fixed `/auth/logout-complete` URL instead, which is what gets
  /// registered with Auth0. See design.md's "Add a second local route" decision.
  func logoutURL(returnTo: String) -> String {
    let logoutCompleteBase = callbackURL.replacingOccurrences(
      of: "/auth/callback", with: "/auth/logout-complete")
    let encodedReturnTo =
      returnTo.addingPercentEncoding(withAllowedCharacters: Self.unreservedCharacters) ?? "/"
    let logoutCompleteURL = "\(logoutCompleteBase)?return_to=\(encodedReturnTo)"
    let encodedLogoutCompleteURL =
      logoutCompleteURL.addingPercentEncoding(withAllowedCharacters: Self.unreservedCharacters)
      ?? logoutCompleteURL

    let encodedClientID =
      clientID.addingPercentEncoding(withAllowedCharacters: Self.unreservedCharacters) ?? clientID
    var components = URLComponents(string: "https://\(domain)/v2/logout")!
    components.percentEncodedQuery =
      "client_id=\(encodedClientID)&returnTo=\(encodedLogoutCompleteURL)"
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
