import Foundation

/// Verify actual handler state, because a system setter's error does not establish
/// that the requested change failed (or that another scheme still needs setting).
@MainActor
public enum DefaultBrowserSetup {
    public enum Outcome: Equatable, Sendable {
        case active
        case needsSystemSettings(errorDomain: String?, errorCode: Int?)
    }
    public static let schemes = ["http", "https"]
    public static func isActive(bundleID: String, handler: (String) -> String?) -> Bool {
        !bundleID.isEmpty && schemes.allSatisfy { handler($0)?.caseInsensitiveCompare(bundleID) == .orderedSame }
    }
    public static func activate(bundleID: String, handler: (String) -> String?, setHandler: (String) async throws -> Void) async -> Outcome {
        guard !bundleID.isEmpty else { return .needsSystemSettings(errorDomain: nil, errorCode: nil) }
        for scheme in schemes {
            // Setting http can also set https. Check again before each request.
            if handler(scheme)?.caseInsensitiveCompare(bundleID) == .orderedSame { continue }
            do { try await setHandler(scheme) }
            catch {
                if isActive(bundleID: bundleID, handler: handler) { return .active }
                let detail = error as NSError
                return .needsSystemSettings(errorDomain: detail.domain, errorCode: detail.code)
            }
        }
        return isActive(bundleID: bundleID, handler: handler) ? .active : .needsSystemSettings(errorDomain: nil, errorCode: nil)
    }
}
