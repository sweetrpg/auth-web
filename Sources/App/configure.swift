import Logging
import OTel
import Redis
import RedisSessionDriver
import Tracing
import Vapor

// TODO: HEALTH_TOKEN-gated deep health check (see docs/service-conventions.md's Health checks
// section) once there's something worth deep-checking beyond "is the process up" - Redis here is
// the session store of record for the whole suite, so a future deep check should probably ping it.

public func configure(_ app: Application) async throws {
  // Structured JSON logging is bootstrapped once in entrypoint.swift, not here - LoggingSystem's
  // bootstrap can only run once per process; entrypoint.swift also calls configure(_:) for the
  // real binary, so a second call here would crash on every real startup, not just under test.

  // Bootstrap distributed tracing via OTLP/gRPC to the cluster's Tempo collector. Uses
  // OTEL_EXPORTER_OTLP_ENDPOINT env var (same endpoint the Go services export to via HTTP,
  // but this app uses gRPC per swift-otel's available transports).
  try await TracingSetup.bootstrap(app)
  app.http.server.configuration.hostname = "0.0.0.0"
  app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080

  app.middleware.use(SentryMiddleware())

  // Shared cookie name, unlike every other frontend's own per-app session - this app is the sole
  // writer of the session every other frontend reads. See design.md's "Shared session across
  // every frontend" decision in platform's add-user-api-authn-authz change. Vapor's default
  // cookieFactory already sets Path=/, which is what makes this cookie visible to every other
  // frontend on the same host.
  app.sessions.configuration.cookieName = "sweetrpg_session"
  if let redisHost = Environment.get("REDIS_HOST"), !redisHost.isEmpty {
    let redisPort = Environment.get("REDIS_PORT").flatMap(Int.init) ?? 6379
    let redisDB = Environment.get("REDIS_DB").flatMap(Int.init) ?? 0
    app.redis.configuration = try RedisConfiguration(
      hostname: redisHost,
      port: redisPort,
      password: Environment.get("REDIS_PASS"),
      database: redisDB
    )
    // Not `.redis` (Vapor's stock RedisSessionsDriver): that driver propagates Redis errors
    // straight through SessionsMiddleware, which runs on every request, so a Redis outage would
    // 500 the whole app. ResilientRedisSessionDriver (sweetrpg/redis-session-driver) degrades to
    // "treated as logged out" instead - see its doc comment.
    app.sessions.use { _ in ResilientRedisSessionDriver() }
  } else {
    app.logger.warning(
      "REDIS_HOST not set - using in-memory sessions. Fine for local development only: every other frontend expects to read sessions from the shared Redis store."
    )
    app.sessions.use(.memory)
  }
  app.middleware.use(app.sessions.middleware)

  // No AuthRequiredMiddleware here, unlike catalog-web/admin-web: this app's whole job is being
  // reachable while unauthenticated, so it can establish a session in the first place.

  // Gates only /auth/login - see MaintenanceModeMiddleware's doc comment for why the callback
  // and logout routes are deliberately excluded.
  app.middleware.use(MaintenanceModeMiddleware())

  try routes(app)
}
