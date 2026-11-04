import Foundation
import Vapor

/// The standard three-line footer (`standard-site-footer`) as an HTML fragment, for this app's
/// standalone pages. No footer CSS here: the look comes from `shared-web`'s stylesheet, which
/// the pages link.
enum SiteFooter {
  static func html(meta: FooterMeta, buildDate: String, buildHash: String, l10n: [String: String])
    -> String
  {
    let t = { (key: String) in I18n.localize(key, in: l10n).htmlEscaped }
    return """
      <footer class="footer">
        <span class="footer-line">&copy; \(meta.year) Pilgrimage Software &middot; <a href="https://github.com/sweetrpg" target="_blank" rel="noopener">GitHub</a></span>
        <span class="footer-line"><a href="\(meta.termsURL.htmlEscaped)">\(t("footer.terms"))</a> &middot; <a href="\(meta.privacyURL.htmlEscaped)">\(t("footer.privacy"))</a> &middot; <a href="\(meta.supportURL.htmlEscaped)">\(t("footer.support"))</a></span>
        <span class="footer-line footer-build">\(meta.versionLabel.htmlEscaped) &middot; built \(buildDate.htmlEscaped) / \(buildHash.htmlEscaped)</span>
      </footer>
      """
  }
}

extension Request {
  /// Site root for links to `main-web`'s pages; the same setting the other frontends use.
  var rootURL: String { Environment.get("ROOT_URL") ?? "/" }

  var sharedURL: String { Environment.get("SHARED_URL") ?? "http://localhost:8081" }

  var siteFooterHTML: String {
    SiteFooter.html(
      meta: FooterMeta(rootURL: rootURL, version: buildInfo.version),
      buildDate: buildInfo.date, buildHash: String(buildInfo.sha.prefix(8)), l10n: l10n)
  }
}
