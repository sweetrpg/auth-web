import Foundation
import Vapor

extension Request {
  private static let sessionKey = "user"

  /// `docs/frontend-conventions.md`'s "Shared session schema" documents `expiry` as an RFC 3339
  /// timestamp string - every reader across the suite (`catalog-web`, `admin-web`, and
  /// `main-web`'s Rust `chrono::DateTime<Utc>`) expects that shape. Plain `JSONEncoder`/
  /// `JSONDecoder` default to `.deferredToDate`, which encodes `Date` as a raw `Double` (seconds
  /// since 2001) instead - silently compatible with this app's own reads (and, coincidentally,
  /// catalog-web's/admin-web's, since they defaulted the same way), but not RFC 3339, so
  /// `main-web` failed to parse it and treated every session as logged-out. `.iso8601` makes
  /// this app actually conform to the schema it defines.
  private static let sessionDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()

  private static let sessionEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  var currentUser: SessionUser? {
    get {
      guard let json = session.data[Self.sessionKey],
        let data = json.data(using: .utf8),
        let user = try? Self.sessionDecoder.decode(SessionUser.self, from: data),
        user.expiry > Date()
      else { return nil }
      return user
    }
    set {
      guard let newValue,
        let data = try? Self.sessionEncoder.encode(newValue),
        let json = String(data: data, encoding: .utf8)
      else {
        session.data[Self.sessionKey] = nil
        return
      }
      session.data[Self.sessionKey] = json
    }
  }
}
