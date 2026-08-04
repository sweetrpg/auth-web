import AdminAPIClient
import Vapor

/// Abstraction over `AdminClient.fetchMaintenanceModes(scopes:)` so `MaintenanceModeMiddleware`
/// can be tested against a fake instead of a real network call. `AdminClient` (an actor from the
/// external admin-api-client.swift package) already satisfies this shape, so it conforms for
/// free below - no wrapping or extra allocation for the production path.
protocol MaintenanceModeChecking: Sendable {
  func fetchMaintenanceModes(scopes: [String]) async -> [MaintenanceMode]
}

extension AdminClient: MaintenanceModeChecking {}

extension Application {
  private struct MaintenanceModeCheckerKey: StorageKey {
    typealias Value = any MaintenanceModeChecking
  }

  /// Lazily built from `ADMIN_API_URL` on first access. Unset -> `AdminClient` gets a `nil`
  /// base URL and is permanently disabled (fail-open by the SDK's own contract, not something
  /// this app has to re-implement) - this is the required default so environments that haven't
  /// configured admin-api yet are unaffected.
  var maintenanceModeChecker: any MaintenanceModeChecking {
    get {
      guard let checker = storage[MaintenanceModeCheckerKey.self] else {
        let checker = AdminClient(baseURL: Environment.get("ADMIN_API_URL"))
        storage[MaintenanceModeCheckerKey.self] = checker
        return checker
      }
      return checker
    }
    set { storage[MaintenanceModeCheckerKey.self] = newValue }
  }
}
