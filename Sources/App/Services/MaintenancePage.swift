import AdminAPIClient
import Foundation

/// Minimal standalone maintenance page. This app has no Leaf renderer and no existing page of
/// its own to match - every route either redirects to Auth0 or back to `return_to` (see
/// Package.swift's dependencies comment) - so this is a small dependency-free HTML string rather
/// than pulling in Leaf for a single static page.
enum MaintenancePage {
  static func render(_ mode: MaintenanceMode, l10n: [String: String] = [:]) -> String {
    let windowLine = formattedWindow(startsAt: mode.startsAt, endsAt: mode.endsAt, l10n: l10n)
    return """
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>\(escape(mode.label)) - SweetRPG</title>
        <style>
          :root { color-scheme: light dark; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            max-width: 32rem;
            margin: 4rem auto;
            padding: 0 1.5rem;
            line-height: 1.5;
            color: #1a1a1a;
            background: #fafafa;
          }
          @media (prefers-color-scheme: dark) {
            body { color: #eaeaea; background: #16161a; }
          }
          h1 { font-size: 1.5rem; margin-bottom: 0.5rem; }
          p { margin: 0.5rem 0; }
          .window { color: #666; font-size: 0.9rem; }
          @media (prefers-color-scheme: dark) { .window { color: #999; } }
        </style>
      </head>
      <body>
        <h1>\(escape(mode.label))</h1>
        <p>\(escape(mode.description))</p>
        \(windowLine.map { "<p class=\"window\">\($0)</p>" } ?? "")
      </body>
      </html>
      """
  }

  private static func formattedWindow(startsAt: String, endsAt: String?, l10n: [String: String])
    -> String?
  {
    guard !startsAt.isEmpty else { return nil }
    let prefix = I18n.localize("maintenance.since_prefix", in: l10n)
    let suffix = I18n.localize("maintenance.since_suffix", in: l10n)
    if let endsAt, !endsAt.isEmpty {
      let separator = I18n.localize("maintenance.window_separator", in: l10n)
      return "\(escape(startsAt)) \(separator) \(escape(endsAt))"
    }
    return "\(escape(prefix))\(escape(startsAt))\(escape(suffix))"
  }

  private static func escape(_ raw: String) -> String {
    raw
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
