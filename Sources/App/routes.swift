import Vapor

func routes(_ app: Application) throws {
  // Shallow liveness only.
  app.get("status", "ping") { req -> [String: String] in
    [
      "status": "ok", "hostname": Environment.get("HOSTNAME") ?? "unknown",
      "version": req.buildInfo.version,
    ]
  }

  try app.register(collection: AuthController())
}
