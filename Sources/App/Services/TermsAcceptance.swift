import Vapor

/// The `terms_accepted` record `users-api` keeps on a user's profile.
struct TermsAcceptance: Content, Equatable {
  let version: String
  let acceptedAt: String

  enum CodingKeys: String, CodingKey {
    case version
    case acceptedAt = "accepted_at"
  }
}

/// A dotted numeric terms version such as `1`, `1.0` or `2.1.3`. Missing trailing components
/// compare as zero, so `1` equals `1.0`.
struct TermsVersion: Comparable, Equatable {
  let parts: [Int]

  init?(_ raw: String) {
    let pieces = raw.split(separator: ".", omittingEmptySubsequences: false)
    let numbers = pieces.compactMap { Int($0) }
    guard !pieces.isEmpty, numbers.count == pieces.count, numbers.allSatisfy({ $0 >= 0 }) else {
      return nil
    }
    parts = numbers
  }

  static func < (lhs: TermsVersion, rhs: TermsVersion) -> Bool {
    for index in 0..<max(lhs.parts.count, rhs.parts.count) {
      let left = index < lhs.parts.count ? lhs.parts[index] : 0
      let right = index < rhs.parts.count ? rhs.parts[index] : 0
      if left != right { return left < right }
    }
    return false
  }

  static func == (lhs: TermsVersion, rhs: TermsVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// The platform's required terms version, from `REQUIRED_TERMS_VERSION` and
/// `TERMS_VERSION_MATERIAL`. Publishing a new version changes these two settings, not code.
struct TermsPolicy: Equatable {
  struct ConfigError: Error, CustomStringConvertible {
    let description: String
  }

  let requiredVersion: String
  let isMaterial: Bool
  private let required: TermsVersion

  init(requiredVersion: String, isMaterial: Bool) throws {
    guard let parsed = TermsVersion(requiredVersion) else {
      throw ConfigError(
        description: "REQUIRED_TERMS_VERSION '\(requiredVersion)' is not a dotted numeric version")
    }
    self.requiredVersion = requiredVersion
    self.isMaterial = isMaterial
    self.required = parsed
  }

  /// `nil` when `REQUIRED_TERMS_VERSION` is unset (the gate has nothing to enforce); throws when
  /// either setting is present but malformed, so a typo fails startup instead of silently
  /// disabling or mis-enforcing the gate.
  static func fromEnvironment() throws -> TermsPolicy? {
    guard let version = Environment.get("REQUIRED_TERMS_VERSION"), !version.isEmpty else {
      return nil
    }
    let material: Bool
    switch Environment.get("TERMS_VERSION_MATERIAL")?.lowercased() {
    case "true": material = true
    case "false": material = false
    default:
      throw ConfigError(description: "TERMS_VERSION_MATERIAL must be 'true' or 'false'")
    }
    return try TermsPolicy(requiredVersion: version, isMaterial: material)
  }

  /// A user with no record must accept. A user whose accepted version is older than the required
  /// one must accept only when the new version is material; a non-material update never blocks.
  func needsAcceptance(_ accepted: TermsAcceptance?) -> Bool {
    guard let accepted else { return true }
    guard isMaterial else { return false }
    guard let have = TermsVersion(accepted.version) else { return true }
    return have < required
  }
}

/// Reads and writes the signed-in user's terms acceptance on `users-api`, always with that
/// user's own access token.
protocol TermsStoring: Sendable {
  func fetch(accessToken: String, on client: Client) async throws -> TermsAcceptance?
  func record(version: String, accessToken: String, on client: Client) async throws
}

extension Application {
  private struct TermsPolicyKey: StorageKey { typealias Value = TermsPolicy }
  private struct TermsStoreKey: StorageKey { typealias Value = any TermsStoring }

  /// `nil` disables the gate; set once in `configure`.
  var termsPolicy: TermsPolicy? {
    get { storage[TermsPolicyKey.self] }
    set { storage[TermsPolicyKey.self] = newValue }
  }

  var termsStore: any TermsStoring {
    get { storage[TermsStoreKey.self] ?? UsersAPITermsStore() }
    set { storage[TermsStoreKey.self] = newValue }
  }
}
