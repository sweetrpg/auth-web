// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "auth-web",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        // 🔴 Redis-backed session storage, shared with every other frontend that reads it.
        .package(url: "https://github.com/vapor/redis.git", from: "4.10.0"),
        // 🛡️ Fail-open Redis session driver - degrades to "treated as logged out" instead of
        // 500ing when Redis is unreachable. 0.1.0 adds the idle/absolute expiry policy
        // (platform's session-expiration-policy change).
        .package(url: "https://github.com/sweetrpg/redis-session-driver.git", from: "0.1.0"),
        // 🚧 admin-api maintenance-mode/banner client - fail-open by contract, never throws.
        .package(url: "https://github.com/sweetrpg/admin-api-client.swift.git", branch: "develop"),
        // 🩻 Distributed tracing API + OTLP exporter, matching the Go services' OTLP/HTTP
        // export to the cluster's Tempo collector (docs/service-conventions.md's Telemetry
        // section).
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.0.0"),
        .package(url: "https://github.com/swift-otel/swift-otel.git", from: "0.8.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Redis", package: "redis"),
                .product(name: "RedisSessionDriver", package: "redis-session-driver"),
                .product(name: "AdminAPIClient", package: "admin-api-client.swift"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "OTel", package: "swift-otel"),
                .product(name: "OTLPGRPC", package: "swift-otel"),
            ],
            // No Leaf/rendered pages: every "log in" link across the suite points straight at
            // /auth/login, which redirects immediately - this app has no page of its own to show.
            swiftSettings: [
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor"),
            ]
        ),
    ]
)
