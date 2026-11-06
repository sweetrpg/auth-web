import Testing

@testable import App

@Suite("displayName(from:)")
struct DisplayNameTests {
  @Test("prefers the name claim")
  func name() {
    #expect(
      displayName(from: ["name": "Sha Zean", "nickname": "shazean", "email": "a@b.c"]) == "Sha Zean"
    )
  }

  @Test("falls back to the nickname when the name is missing or empty")
  func nickname() {
    #expect(displayName(from: ["nickname": "shazean", "email": "a@b.c"]) == "shazean")
    #expect(displayName(from: ["name": "  ", "nickname": "shazean"]) == "shazean")
  }

  @Test("then the email, then the placeholder")
  func emailThenPlaceholder() {
    #expect(displayName(from: ["email": "a@b.c"]) == "a@b.c")
    #expect(displayName(from: [:]) == "User")
  }
}
