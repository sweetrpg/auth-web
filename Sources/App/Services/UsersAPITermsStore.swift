import Vapor

/// `TermsStoring` backed by `users-api`: `GET /profile` carries `terms_accepted`
/// (`{version, accepted_at}` or `null`), and `PUT /profile/terms` records an acceptance. Both
/// resolve the user from the bearer token, never from a client-supplied ID.
struct UsersAPITermsStore: TermsStoring {
  var baseURL: String =
    Environment.get("USERS_API_URL") ?? "http://api-v1.sweetrpg-users.svc.cluster.local:8000"

  struct ProfileResponse: Content {
    let termsAccepted: TermsAcceptance?

    enum CodingKeys: String, CodingKey { case termsAccepted = "terms_accepted" }
  }

  private struct RecordRequest: Content { let version: String }

  enum Failure: Error { case unexpectedStatus(HTTPStatus) }

  func fetch(accessToken: String, on client: Client) async throws -> TermsAcceptance? {
    let response = try await client.get(URI(string: "\(baseURL)/profile")) { req in
      req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
    }
    // A 404 means the user has no profile yet, which is not the same as "has not accepted":
    // there is nothing to write an acceptance onto, so it surfaces as a failure and the caller
    // lets the user in.
    guard response.status == .ok else { throw Failure.unexpectedStatus(response.status) }
    return try response.content.decode(ProfileResponse.self).termsAccepted
  }

  func record(version: String, accessToken: String, on client: Client) async throws {
    let response = try await client.put(URI(string: "\(baseURL)/profile/terms")) { req in
      req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
      try req.content.encode(RecordRequest(version: version))
    }
    // 409 terms_version_not_newer: a newer version is already on record, so this user is covered.
    guard response.status == .ok || response.status == .conflict else {
      throw Failure.unexpectedStatus(response.status)
    }
  }
}
