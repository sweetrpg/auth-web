import Vapor

/// Evaluates a boolean feature flag. Implementations must never throw: an unreachable or slow
/// flag source degrades to the caller-supplied default (PADR-0014, fail-open).
protocol FeatureFlagEvaluating: Sendable {
  func isEnabled(_ key: String, default defaultValue: Bool, on client: Client) async -> Bool
}

/// Reads flags from the `flagd` sidecar the OpenFeature Operator injects (see the
/// `openfeature.dev/*` annotations in `kubernetes/base/deployment.yaml`) through its OFREP HTTP
/// endpoint. There is no server-side OpenFeature SDK for Swift, so this is the plain-REST path
/// described in `docs/swift-service-conventions.md`'s "Feature flags" section.
struct OFREPFeatureFlags: FeatureFlagEvaluating {
  var baseURL: String = Environment.get("FLAGD_OFREP_URL") ?? "http://localhost:8016"
  /// Flag evaluation sits on the login path, so a hung sidecar must not stall a login.
  var timeout: Duration = .milliseconds(500)

  private struct Evaluation: Decodable { let value: Bool }

  func isEnabled(_ key: String, default defaultValue: Bool, on client: Client) async -> Bool {
    let uri = URI(string: "\(baseURL)/ofrep/v1/evaluate/flags/\(key)")
    do {
      return try await withThrowingTaskGroup(of: Bool.self) { group in
        group.addTask {
          let response = try await client.post(uri) { req in
            try req.content.encode(["context": [String: String]()])
          }
          guard response.status == .ok else { throw Abort(response.status) }
          return try response.content.decode(Evaluation.self).value
        }
        group.addTask {
          try await Task.sleep(for: timeout)
          throw Abort(.gatewayTimeout)
        }
        defer { group.cancelAll() }
        return try await group.next() ?? defaultValue
      }
    } catch {
      return defaultValue
    }
  }
}

extension Application {
  private struct FeatureFlagsKey: StorageKey { typealias Value = any FeatureFlagEvaluating }

  var featureFlags: any FeatureFlagEvaluating {
    get { storage[FeatureFlagsKey.self] ?? OFREPFeatureFlags() }
    set { storage[FeatureFlagsKey.self] = newValue }
  }
}
