import Foundation
import Lingo
import Vapor

/// Localization support - see sweetrpg/platform's openspec change `full-localization-web-apps`.
///
/// Locale resolution order:
/// 1. `locale` cookie, when its value maps to a loaded localization table
/// 2. First tag of the Accept-Language header's base subtag (before `-`, `;q=` stripped),
///    when supported
/// 3. English (`en`) fallback
enum I18n {
  static let defaultLocale = "en"

  nonisolated(unsafe) private static var tables: [String: [String: String]] = [:]
  private static let lock = NSLock()

  /// Loads every `Resources/Localizations/<code>.json` into memory at startup.
  static func load() {
    let dir: String?
    #if canImport(ObjectiveC)
      dir = Bundle.module.resourcePath.map {
        ($0 as NSString).appendingPathComponent("Localizations")
      }
    #else
      dir = nil
    #endif
    guard let path = dir, let files = try? FileManager.default.contentsOfDirectory(atPath: path)
    else {
      return
    }
    var loaded: [String: [String: String]] = [:]
    for file in files where file.hasSuffix(".json") {
      let code = String(file.dropLast(".json".count))
      guard let url = URL(string: "\(path)/\(file)"), let data = try? Data(contentsOf: url),
        let table = try? JSONDecoder().decode([String: String].self, from: data)
      else { continue }
      loaded[code] = table
    }
    if loaded[defaultLocale] == nil {
      loaded[defaultLocale] = [:]
    }
    lock.lock()
    defer { lock.unlock() }
    tables = loaded
  }

  /// Resolves the request locale and returns its flat string table (falling back to English
  /// for missing keys is done by `localize`). Exposed so render contexts can carry it.
  static func table(for req: Request) -> [String: String] {
    let locale = resolveLocale(
      cookie: req.cookies["locale"]?.string,
      acceptLanguage: req.headers[.acceptLanguage].first)
    return strings(for: locale)
  }

  static func resolveLocale(cookie: String?, acceptLanguage: String?) -> String {
    lock.lock()
    defer { lock.unlock() }
    if let cookie, !cookie.isEmpty, tables[cookie] != nil {
      return cookie
    }
    if let acceptLanguage {
      let tag = acceptLanguage.split(separator: ",").first.map(String.init) ?? ""
      let base = tag.split(separator: ";").first.map(String.init) ?? ""
      let subtag = base.split(separator: "-").first.map(String.init) ?? ""
      if !subtag.isEmpty, tables[subtag] != nil {
        return subtag
      }
    }
    return defaultLocale
  }

  static func strings(for code: String) -> [String: String] {
    lock.lock()
    defer { lock.unlock() }
    guard let table = tables[code] else { return tables[defaultLocale] ?? [:] }
    var merged = tables[defaultLocale] ?? [:]
    for (key, value) in table { merged[key] = value }
    return merged
  }

  static func localize(_ key: String, in table: [String: String]) -> String {
    table[key] ?? key
  }
}

extension Request {
  /// Flat translated-string table for this request's resolved locale, suitable for embedding
  /// directly in render contexts as `l10n`.
  var l10n: [String: String] { I18n.table(for: self) }
}
