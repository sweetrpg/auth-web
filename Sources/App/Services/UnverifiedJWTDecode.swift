import Foundation

/// SECURITY: this decodes the JWT payload without verifying its signature. Only safe here
/// because the token arrives directly from Auth0's token endpoint over a server-to-server TLS
/// connection in `AuthController.callback`, purely to read `sub`/`name`/`email` for display - the
/// roles that actually matter for authorization come from `users-api`'s verified `/authz/check`
/// response instead, whose `sub` is cross-checked against this decode's `sub` before either is
/// trusted. Do not extend this decoder's role beyond display without adding real signature
/// verification against Auth0's JWKS endpoint.
func decodeUnverifiedJWTPayload(_ jwt: String) -> [String: Any]? {
  let parts = jwt.split(separator: ".")
  guard parts.count == 3 else { return nil }
  var base64 = String(parts[1])
    .replacingOccurrences(of: "-", with: "+")
    .replacingOccurrences(of: "_", with: "/")
  while base64.count % 4 != 0 { base64 += "=" }
  guard let data = Data(base64Encoded: base64),
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else { return nil }
  return json
}

/// The display name to seed a new user with: the `name` claim, else the `nickname` claim (a GitHub
/// login with no public name still has one), else the email, else a placeholder. Empty strings
/// count as absent.
func displayName(from claims: [String: Any]) -> String {
  for key in ["name", "nickname", "email"] {
    if let value = claims[key] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty {
      return value
    }
  }
  return "User"
}
