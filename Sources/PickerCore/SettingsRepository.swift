import Foundation

public struct SettingsRepository: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public struct Loaded: Sendable {
        public let configuration: Configuration
        public let recoveredFromBackup: Bool
    }
    private var backupURL: URL { url.appendingPathExtension("backup") }
    public func load() throws -> Loaded {
        guard FileManager.default.fileExists(atPath: url.path) else { return Loaded(configuration: Configuration(), recoveredFromBackup: false) }
        do { return Loaded(configuration: try decode(url), recoveredFromBackup: false) }
        catch {
            // A newer schema must never be downgraded or replaced with a backup.
            if case PickerError.unsupportedVersion = error { throw error }
            if let backup = try? decode(backupURL) { return Loaded(configuration: backup, recoveredFromBackup: true) }
            throw error
        }
    }
    private func decode(_ source: URL) throws -> Configuration {
        let data = try Data(contentsOf: source)
        guard data.count < 4_000_000 else { throw PickerError.invalidRule("Settings file is unexpectedly large.") }
        return try JSONDecoder().decode(Configuration.self, from: data)
    }
    public func save(_ configuration: Configuration) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        _ = try JSONDecoder().decode(Configuration.self, from: data)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            // Preserve unreadable data for manual recovery; don't destroy a valid backup.
            if (try? decode(url)) != nil { try Data(contentsOf: url).write(to: backupURL, options: .atomic) }
            else { try Data(contentsOf: url).write(to: url.appendingPathExtension("damaged-" + UUID().uuidString), options: .atomic) }
        }
        try data.write(to: url, options: .atomic)
    }
}
