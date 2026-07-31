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
}
