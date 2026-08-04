import AdminAPIClient
import Foundation

/// Minimal standalone maintenance page. This app has no Leaf renderer and no existing page of
/// its own to match - every route either redirects to Auth0 or back to `return_to` (see
/// Package.swift's dependencies comment) - so this is a small dependency-free HTML string rather
/// than pulling in Leaf for a single static page.
enum MaintenancePage {
  static func render(_ mode: MaintenanceMode) -> String {
    let windowLine = formattedWindow(startsAt: mode.startsAt, endsAt: mode.endsAt)
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

  private static func formattedWindow(startsAt: String, endsAt: String?) -> String? {
    guard !startsAt.isEmpty else { return nil }
    if let endsAt, !endsAt.isEmpty {
      return "\(escape(startsAt)) &ndash; \(escape(endsAt))"
    }
    return "Since \(escape(startsAt))"
  }

  private static func escape(_ raw: String) -> String {
    raw
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
