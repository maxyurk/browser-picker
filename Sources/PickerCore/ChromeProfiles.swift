import Foundation

public enum ChromeProfiles {
    public struct Profile: Equatable, Sendable { public let directory: String; public let name: String }
    public static func validDirectory(_ name: String) -> Bool {
        name == "Default" || (name.hasPrefix("Profile ") && !name.dropFirst(8).isEmpty && name.dropFirst(8).allSatisfy { $0.isASCII && $0.isNumber })
    }
    public static func read(_ data: Data) -> [Profile] {
        guard data.count < 8_000_000,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any], let cache = profile["info_cache"] as? [String: [String: Any]] else { return [] }
        return cache.compactMap { directory, info in
            guard validDirectory(directory) else { return nil }
            let name = (info["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Profile(directory: directory, name: (name?.isEmpty == false ? name : nil) ?? directory)
        }.sorted { $0.directory.localizedStandardCompare($1.directory) == .orderedAscending }
    }
    public static func arguments(url: URL, profile: String?, privateWindow: Bool) throws -> [String] {
        var result: [String] = []
        if let profile {
            guard validDirectory(profile) else { throw PickerError.invalidProfile }
            result.append("--profile-directory=" + profile)
        }
        if privateWindow { result.append("--incognito") }
        result.append(try OpenTarget.process(url, unwrap: false, cleanTracking: false).absoluteString)
        return result
    }
}
