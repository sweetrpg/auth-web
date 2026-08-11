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
        // 500ing when Redis is unreachable. Pinned to the finish-shared-session-rollout branch
        // for its TTL/expiry support (platform#26) until that PR merges and cuts a release -
        // repoint at a tagged `from:` version once sweetrpg/redis-session-driver#5 lands.
        .package(
            url: "https://github.com/sweetrpg/redis-session-driver.git",
            branch: "26-finish-shared-session-rollout"),
        // 🚧 admin-api maintenance-mode/banner client - fail-open by contract, never throws.
        .package(url: "https://github.com/sweetrpg/admin-api-client.swift.git", branch: "develop"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Redis", package: "redis"),
                .product(name: "RedisSessionDriver", package: "redis-session-driver"),
                .product(name: "AdminAPIClient", package: "admin-api-client.swift"),
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
