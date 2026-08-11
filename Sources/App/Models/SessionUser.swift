import Vapor

/// The identity every other frontend reads out of the shared session store - see design.md's
/// "Shared session across every frontend" decision in platform's add-user-api-authn-authz
/// change. Unlike catalog-web's/admin-web's own former SessionUser, `roles` comes from
/// `users-api`'s verified `/authz/check` response, not an unverified local ID-token decode.
struct SessionUser: Codable {
  let sub: String
  let name: String
  let email: String?
  let roles: [String]
  /// The Auth0 access token from the code exchange, so a frontend making an authenticated
  /// write call to a backend (e.g. catalog-api's `/authz/check`-gated endpoints) has something
  /// to forward as a Bearer token - see platform's volume-edit-with-approval-workflow change.
  /// No refresh-token flow exists in this app, so once this token's own lifetime expires, a
  /// write call fails with 401 until the user logs in again; that degradation is accepted
  /// rather than adding token refresh, which is out of scope here.
  let accessToken: String
  /// When this session becomes invalid - matches the Auth0 access token's own `expires_in`
  /// lifetime from the token exchange. Every reader must treat a session at or past this
  /// timestamp as "no session found," not stale data - see `sweetrpg/platform`'s
  /// `docs/frontend-conventions.md` ("Shared session schema"). Enforced independently at the
  /// Redis key level by `ResilientRedisSessionDriver`'s TTL; this field is what lets
  /// application code explain *why* a session ended and display "signed in until X."
  let expiry: Date
}
