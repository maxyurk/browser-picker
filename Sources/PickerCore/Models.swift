import Foundation

public enum PickerError: Error, LocalizedError, Equatable {
    case invalidURL, invalidDomain, invalidRule(String), unsupportedVersion(Int), invalidProfile
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a web link, file URL, or file path."
        case .invalidDomain: "Enter a hostname, such as github.com (no path or port)."
        case .invalidRule(let reason): reason
        case .unsupportedVersion(let version): "Settings version \(version) is newer than this app supports."
        case .invalidProfile: "This Chrome profile is no longer available. Refresh the browsers in Settings."
        }
    }
}

public struct Destination: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let bundleID: String
    public let appPath: String
    public let profile: String?
    public let supportsPrivate: Bool
    public init(id: String, name: String, bundleID: String, appPath: String, profile: String? = nil, supportsPrivate: Bool = false) {
        self.id = id; self.name = name; self.bundleID = bundleID; self.appPath = appPath
        self.profile = profile; self.supportsPrivate = supportsPrivate
    }
}

public struct Rule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var domain: String
    public var includeSubdomains: Bool
    public var pathPrefix: String
    public var sourceBundleID: String
    public var destinationID: String
    public var enabled: Bool
    public var privateWindow: Bool
    public var localFilesOnly: Bool
    public init(id: UUID = UUID(), domain: String = "", includeSubdomains: Bool = true, pathPrefix: String = "", sourceBundleID: String = "", destinationID: String = "prompt", enabled: Bool = true, privateWindow: Bool = false, localFilesOnly: Bool = false) {
        self.id = id; self.domain = domain; self.includeSubdomains = includeSubdomains
        self.pathPrefix = pathPrefix; self.sourceBundleID = sourceBundleID
        self.destinationID = destinationID; self.enabled = enabled; self.privateWindow = privateWindow; self.localFilesOnly = localFilesOnly
    }
    enum CodingKeys: CodingKey { case id, domain, includeSubdomains, pathPrefix, sourceBundleID, destinationID, enabled, privateWindow, localFilesOnly }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        domain = try values.decode(String.self, forKey: .domain)
        includeSubdomains = try values.decode(Bool.self, forKey: .includeSubdomains)
        pathPrefix = try values.decode(String.self, forKey: .pathPrefix)
        sourceBundleID = try values.decode(String.self, forKey: .sourceBundleID)
        destinationID = try values.decode(String.self, forKey: .destinationID)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        privateWindow = try values.decode(Bool.self, forKey: .privateWindow)
        localFilesOnly = try values.decodeIfPresent(Bool.self, forKey: .localFilesOnly) ?? false
    }
    public func validated() throws -> Rule {
        var result = self
        result.domain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if localFilesOnly {
            result.domain = ""; result.includeSubdomains = false
        } else if !result.domain.isEmpty {
            result.domain = try DomainPattern.normalize(result.domain)
            if result.domain.hasPrefix("*.") { result.includeSubdomains = true }
        }
        result.sourceBundleID = sourceBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        result.pathPrefix = pathPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard localFilesOnly || !result.domain.isEmpty || !result.sourceBundleID.isEmpty else {
            throw PickerError.invalidRule("Choose Local files, or add a website or a source app.")
        }
        guard result.pathPrefix.isEmpty || result.pathPrefix.hasPrefix("/") else {
            throw PickerError.invalidRule("Path prefixes must start with /.")
        }
        guard !destinationID.isEmpty else { throw PickerError.invalidRule("Choose a destination.") }
        return result
    }
    public func matches(_ url: URL, source: String?) -> Bool {
        return matches(host: Self.matchingHost(url) ?? "", path: url.path, source: source, isFile: url.isFileURL)
    }
    static func matchingHost(_ url: URL) -> String? {
        guard !url.isFileURL else { return nil }
        guard var host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else { return nil }
        if host.contains(":") { host = (try? WebURL.normalizeDomain(host)) ?? host }
        return host
    }
    func matches(host: String, path: String, source: String?, isFile: Bool = false) -> Bool {
        guard enabled else { return false }
        if localFilesOnly && !isFile { return false }
        if !domain.isEmpty && !DomainPattern.matches(host, pattern: domain, includeSubdomains: includeSubdomains) { return false }
        if !sourceBundleID.isEmpty && sourceBundleID != source { return false }
        return pathPrefix.isEmpty || path.hasPrefix(pathPrefix)
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public private(set) var version = 3
    public var defaultDestinationID = "prompt"
    public var hiddenDestinationIDs: Set<String> = []
    public var customBrowserPaths: [String] = []
    public var cleanTracking = false
    public var unwrapRedirects = true
    public var dismissPickerOnOutsideClick = true
    public var rules: [Rule] = []
    public init() {}
    enum CodingKeys: CodingKey { case version, defaultDestinationID, hiddenDestinationIDs, customBrowserPaths, cleanTracking, unwrapRedirects, dismissPickerOnOutsideClick, rules }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard (1...3).contains(storedVersion) else { throw PickerError.unsupportedVersion(storedVersion) }
        // Older apps must reject new rule formats rather than recover an older
        // backup that silently discards them. Existing settings migrate on save.
        version = 3
        defaultDestinationID = try values.decodeIfPresent(String.self, forKey: .defaultDestinationID) ?? "prompt"
        hiddenDestinationIDs = try values.decodeIfPresent(Set<String>.self, forKey: .hiddenDestinationIDs) ?? []
        customBrowserPaths = try values.decodeIfPresent([String].self, forKey: .customBrowserPaths) ?? []
        cleanTracking = try values.decodeIfPresent(Bool.self, forKey: .cleanTracking) ?? false
        unwrapRedirects = try values.decodeIfPresent(Bool.self, forKey: .unwrapRedirects) ?? true
        dismissPickerOnOutsideClick = try values.decodeIfPresent(Bool.self, forKey: .dismissPickerOnOutsideClick) ?? true
        rules = try values.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        rules = try rules.map { try $0.validated() }
        guard Set(rules.map(\.id)).count == rules.count else { throw PickerError.invalidRule("Duplicate rule identifiers in settings.") }
    }
    public mutating func remember(domain: String, destinationID: String, privateWindow: Bool = false) throws {
        let host = try WebURL.normalizeDomain(domain)
        let rule = try Rule(domain: host, destinationID: destinationID, privateWindow: privateWindow).validated()
        // A remembered choice takes precedence, but never overwrites a source-specific rule.
        rules.removeAll { $0.domain == host && $0.sourceBundleID.isEmpty && $0.pathPrefix.isEmpty }
        rules.insert(rule, at: 0)
    }
    public mutating func remember(url: URL, destinationID: String, privateWindow: Bool = false) throws {
        let target = try OpenTarget.process(url, unwrap: false, cleanTracking: false)
        if target.isFileURL {
            let rule = try Rule(destinationID: destinationID, privateWindow: privateWindow, localFilesOnly: true).validated()
            rules.removeAll { $0.localFilesOnly && $0.sourceBundleID.isEmpty && $0.pathPrefix.isEmpty }
            rules.insert(rule, at: 0)
        } else if let host = target.host {
            try remember(domain: host, destinationID: destinationID, privateWindow: privateWindow)
        }
    }
}

public struct LinkRequest: Equatable, Sendable {
    public let url: URL
    public let sourceBundleID: String?
    public let forcePrompt: Bool
    public init(url: URL, sourceBundleID: String? = nil, forcePrompt: Bool = false) {
        self.url = url; self.sourceBundleID = sourceBundleID; self.forcePrompt = forcePrompt
    }
}

public enum Route: Equatable, Sendable {
    case prompt(URL)
    case open(URL, Destination, privateWindow: Bool)
}

public enum Router {
    public static func route(_ request: LinkRequest, configuration: Configuration, destinations: [Destination]) throws -> Route {
        let url = try OpenTarget.process(request.url, unwrap: configuration.unwrapRedirects, cleanTracking: configuration.cleanTracking)
        if request.forcePrompt { return .prompt(url) }
        // Normalize once per incoming URL, rather than once for each candidate rule.
        let host = Rule.matchingHost(url) ?? ""
        let path = url.path
        let isFile = url.isFileURL
        let rule = configuration.rules.first { $0.matches(host: host, path: path, source: request.sourceBundleID, isFile: isFile) }
        let target = rule?.destinationID ?? configuration.defaultDestinationID
        // Missing targets always fall back to a choice; never silently use another account/browser.
        guard target != "prompt", let destination = destinations.first(where: { $0.id == target }) else { return .prompt(url) }
        let privateWindow = rule?.privateWindow ?? false
        guard !privateWindow || destination.supportsPrivate else { return .prompt(url) }
        return .open(url, destination, privateWindow: privateWindow)
    }
}

/// FIFO, preserving every link across concurrent open events and repeated clicks.
public struct RequestQueue: Sendable {
    private var storage: [LinkRequest] = []
    private var head = 0
    public init() {}
    public var count: Int { storage.count - head }
    public mutating func append(_ request: LinkRequest) { storage.append(request) }
    public mutating func pop() -> LinkRequest? {
        guard head < storage.count else { return nil }
        let result = storage[head]; head += 1
        if head == storage.count { storage.removeAll(keepingCapacity: true); head = 0 }
        else if head > 128 && head * 2 > storage.count { storage.removeFirst(head); head = 0 }
        return result
    }
}
