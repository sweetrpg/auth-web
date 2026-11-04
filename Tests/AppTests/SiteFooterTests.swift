import Foundation
import Testing
import VaporTesting

@testable import App

private let l10n = [
  "footer.terms": "Terms of Service", "footer.privacy": "Privacy Policy",
  "footer.support": "Support",
]

@Suite("Standard site footer")
struct SiteFooterTests {
  private func footer(root: String = "https://dev.sweetrpg.com/") -> String {
    SiteFooter.html(
      meta: FooterMeta(rootURL: root, version: "0.14.0"), buildDate: "2026-11-03",
      buildHash: "8c97b95d", l10n: l10n)
  }

  @Test("renders the three lines in order, the last also marked as the build line")
  func threeLinesInOrder() throws {
    let html = footer()
    let copyright = try #require(html.range(of: "Pilgrimage Software"))
    let terms = try #require(html.range(of: "Terms of Service"))
    let build = try #require(html.range(of: "footer-line footer-build"))
    #expect(copyright.lowerBound < terms.lowerBound && terms.lowerBound < build.lowerBound)
    #expect(html.components(separatedBy: "class=\"footer-line").count - 1 == 3)
    #expect(html.contains("v0.14.0 &middot; built 2026-11-03 / 8c97b95d"))
  }

  @Test("the copyright shows the current year, not a literal")
  func currentYear() {
    let year = Calendar(identifier: .gregorian).component(.year, from: Date())
    #expect(footer().contains("&copy; \(year) Pilgrimage Software"))
  }

  @Test("legal links are the site root's /terms, /privacy and /support")
  func legalLinks() {
    let html = footer()
    #expect(html.contains("href=\"https://dev.sweetrpg.com/terms\""))
    #expect(html.contains("href=\"https://dev.sweetrpg.com/privacy\""))
    #expect(html.contains("href=\"https://dev.sweetrpg.com/support\""))
    #expect(footer(root: "/").contains("href=\"/terms\""))
  }

  @Test("the accept and declined pages end with the footer and link the shared stylesheet")
  func pagesCarryFooter() {
    let shared = "https://dev.sweetrpg.com/shared"
    let accept = TermsPage.renderAccept(
      csrf: "t", errorKey: nil, l10n: l10n, footer: footer(), sharedURL: shared)
    let declined = TermsPage.renderDeclined(l10n: l10n, footer: footer(), sharedURL: shared)
    for page in [accept, declined] {
      #expect(page.contains("footer-line footer-build"))
      #expect(page.contains("href=\"\(shared)/static/css/main.css\""))
    }
  }
}
