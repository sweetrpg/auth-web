import Foundation

/// Standalone HTML for the terms-acceptance and declined pages. Same approach as
/// `MaintenancePage`: this app has no Leaf renderer, and these are the only two pages it owns.
/// Text and link colors keep at least 4.5:1 contrast against their background in both schemes.
enum TermsPage {
  /// - Parameter errorKey: l10n key of an inline error to show above the form, if any.
  static func renderAccept(
    csrf: String, errorKey: String?, l10n: [String: String], footer: String, sharedURL: String
  ) -> String {
    let t = { (key: String) in I18n.localize(key, in: l10n).htmlEscaped }
    let error = errorKey.map { "<p class=\"error\" role=\"alert\">\(t($0))</p>" } ?? ""
    return shell(
      title: t("terms.title"), l10n: l10n, footer: footer, sharedURL: sharedURL,
      body: """
        <h1>\(t("terms.title"))</h1>
        <p>\(t("terms.intro"))</p>
        <ul>
          <li><a href="/terms" target="_blank" rel="noopener">\(t("terms.read_terms"))</a></li>
          <li><a href="/privacy" target="_blank" rel="noopener">\(t("terms.read_privacy"))</a></li>
        </ul>
        \(error)
        <form method="post" action="/auth/terms">
          <input type="hidden" name="csrf" value="\(csrf.htmlEscaped)" />
          <p><label><input type="checkbox" name="accept" value="yes" /> \(t("terms.checkbox_label"))</label></p>
          <button type="submit">\(t("terms.submit"))</button>
        </form>
        <form method="post" action="/auth/terms/decline">
          <input type="hidden" name="csrf" value="\(csrf.htmlEscaped)" />
          <button type="submit" class="secondary">\(t("terms.decline"))</button>
        </form>
        """)
  }

  static func renderDeclined(l10n: [String: String], footer: String, sharedURL: String) -> String {
    let t = { (key: String) in I18n.localize(key, in: l10n).htmlEscaped }
    return shell(
      title: t("terms.declined_title"), l10n: l10n, footer: footer, sharedURL: sharedURL,
      body: """
        <h1>\(t("terms.declined_title"))</h1>
        <p>\(t("terms.declined_body"))</p>
        <p><a href="/">\(t("terms.home_link"))</a></p>
        """)
  }

  private static func shell(
    title: String, l10n: [String: String], footer: String, sharedURL: String, body: String
  ) -> String {
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <link rel="stylesheet" href="\(sharedURL.htmlEscaped)/static/css/main.css" />
      <title>\(title) - \(I18n.localize("terms.title_suffix", in: l10n).htmlEscaped)</title>
      <style>
        :root { color-scheme: light dark; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          max-width: 32rem; margin: 4rem auto; padding: 0 1.5rem; line-height: 1.5;
          color: #1a1a1a; background: #fafafa;
        }
        a { color: #0b4f9c; }
        .error { color: #a30000; font-weight: 600; }
        button { font: inherit; padding: 0.5rem 1rem; color: #fff; background: #0b4f9c; border: 0; border-radius: 0.25rem; cursor: pointer; }
        button.secondary { color: #0b4f9c; background: transparent; border: 1px solid #0b4f9c; }
        @media (prefers-color-scheme: dark) {
          body { color: #eaeaea; background: #16161a; }
          a { color: #8ab4ff; }
          .error { color: #ff8a8a; }
          button { color: #16161a; background: #8ab4ff; }
          button.secondary { color: #8ab4ff; background: transparent; border-color: #8ab4ff; }
        }
      </style>
    </head>
    <body>
    \(body)
    \(footer)
    </body>
    </html>
    """
  }
}

extension String {
  var htmlEscaped: String {
    replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
