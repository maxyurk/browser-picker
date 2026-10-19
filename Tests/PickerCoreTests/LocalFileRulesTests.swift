import XCTest
@testable import PickerCore

final class LocalFileRulesTests: XCTestCase {
    private let chrome = Destination(id: "chrome:Work", name: "Chrome · Work", bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", profile: "Profile 2", supportsPrivate: true)
    private let safari = Destination(id: "safari", name: "Safari", bundleID: "com.apple.Safari", appPath: "/Applications/Safari.app")
    private let files = [URL(fileURLWithPath: "/tmp/report.html"), URL(fileURLWithPath: "/Users/example/日本語 #100%+?.pdf"), URL(fileURLWithPath: "/Volumes/Shared/no-extension"), URL(fileURLWithPath: "/tmp/missing.unknown"), URL(string: "file://server/share/folder/")!, URL(string: "file://localhost/tmp/report.html?keep=%2f#section")!]

    private func route(_ url: URL, _ config: Configuration, source: String? = nil, force: Bool = false) throws -> Route {
        try Router.route(LinkRequest(url: url, sourceBundleID: source, forcePrompt: force), configuration: config, destinations: [chrome, safari])
    }

    func testLocalFileRuleAcceptsAllTypesAndLocationsWithoutChangingURLs() throws {
        var config = Configuration()
        config.cleanTracking = true
        config.rules = [try Rule(destinationID: chrome.id, localFilesOnly: true).validated()]
        for file in files {
            XCTAssertTrue(config.rules[0].matches(file, source: nil))
            XCTAssertEqual(try route(file, config), .open(file, chrome, privateWindow: false))
        }
    }

    func testLocalFileRuleNeverCapturesWebLinks() throws {
        var config = Configuration()
        config.defaultDestinationID = safari.id
        config.rules = [Rule(destinationID: chrome.id, localFilesOnly: true)]
        for text in ["https://example.com/report.html", "http://localhost/tmp/report.html", "https://server/share/folder/", "https://example.com/file:///tmp/a"] {
            let web = try XCTUnwrap(URL(string: text))
            XCTAssertFalse(config.rules[0].matches(web, source: nil))
            XCTAssertEqual(try route(web, config), .open(web, safari, privateWindow: false))
        }
    }

    func testFileScopeCombinesWithOptionalPathAndSource() throws {
        let rule = try Rule(pathPrefix: "/tmp/work/", sourceBundleID: "example.sender", destinationID: chrome.id, localFilesOnly: true).validated()
        var config = Configuration(); config.rules = [rule]
        let file = URL(fileURLWithPath: "/tmp/work/report.html")
        XCTAssertEqual(try route(file, config, source: "example.sender"), .open(file, chrome, privateWindow: false))
        XCTAssertEqual(try route(file, config, source: "other.sender"), .prompt(file))
        let other = URL(fileURLWithPath: "/tmp/other/report.html")
        XCTAssertEqual(try route(other, config, source: "example.sender"), .prompt(other))
        let web = URL(string: "https://example.com/tmp/work/report.html")!
        XCTAssertEqual(try route(web, config, source: "example.sender"), .prompt(web))
    }

    func testFileRuleOrderingDisabledAndForcedPicker() throws {
        let file = files[0]
        var config = Configuration()
        config.rules = [Rule(sourceBundleID: "sender", destinationID: safari.id), Rule(destinationID: chrome.id, localFilesOnly: true)]
        XCTAssertEqual(try route(file, config, source: "sender"), .open(file, safari, privateWindow: false))
        config.rules[0].enabled = false
        XCTAssertEqual(try route(file, config, source: "sender"), .open(file, chrome, privateWindow: false))
        XCTAssertEqual(try route(file, config, force: true), .prompt(file))
        config.rules[1].enabled = false
        XCTAssertEqual(try route(file, config), .prompt(file))
    }

    func testAskMissingAndUnsupportedPrivateTargetsStillPrompt() throws {
        for (destination, privateWindow) in [("prompt", false), ("missing", false), (safari.id, true)] {
            var config = Configuration(); config.defaultDestinationID = chrome.id
            config.rules = [Rule(destinationID: destination, privateWindow: privateWindow, localFilesOnly: true)]
            XCTAssertEqual(try route(files[0], config), .prompt(files[0]))
        }
    }

    func testFileRuleCanChooseAProfileAndPrivateWindow() throws {
        var config = Configuration()
        config.hiddenDestinationIDs = [chrome.id]
        config.rules = [Rule(destinationID: chrome.id, privateWindow: true, localFilesOnly: true)]
        XCTAssertEqual(try route(files[0], config), .open(files[0], chrome, privateWindow: true))
    }

    func testSwitchingWebsiteRuleToFilesClearsOnlyWebsiteConditions() throws {
        let rule = try Rule(domain: "old.example.com", pathPrefix: "/tmp/", sourceBundleID: " sender ", destinationID: chrome.id, localFilesOnly: true).validated()
        XCTAssertTrue(rule.localFilesOnly)
        XCTAssertEqual(rule.domain, "")
        XCTAssertFalse(rule.includeSubdomains)
        XCTAssertEqual(rule.pathPrefix, "/tmp/")
        XCTAssertEqual(rule.sourceBundleID, "sender")
        XCTAssertThrowsError(try Rule(pathPrefix: "tmp", localFilesOnly: true).validated())
        XCTAssertThrowsError(try Rule(destinationID: "", localFilesOnly: true).validated())
    }

    func testRememberingAnyFileCreatesOneSharedRule() throws {
        var config = Configuration()
        try config.remember(url: files[0], destinationID: safari.id)
        try config.remember(url: files[1], destinationID: chrome.id, privateWindow: true)
        XCTAssertEqual(config.rules.count, 1)
        XCTAssertTrue(config.rules[0].localFilesOnly)
        XCTAssertEqual(config.rules[0].domain, "")
        XCTAssertEqual(config.rules[0].pathPrefix, "")
        for file in files { XCTAssertEqual(try route(file, config), .open(file, chrome, privateWindow: true)) }
    }

    func testRememberingFilesPreservesWebsiteSourceAndFolderRules() throws {
        let web = Rule(domain: "example.com", destinationID: safari.id)
        let source = Rule(sourceBundleID: "sender", destinationID: safari.id, localFilesOnly: true)
        let folder = Rule(pathPrefix: "/tmp/", destinationID: safari.id, localFilesOnly: true)
        var config = Configuration()
        config.rules = [web, source, folder, Rule(destinationID: safari.id, enabled: false, localFilesOnly: true)]
        try config.remember(url: files[0], destinationID: chrome.id)
        XCTAssertEqual(Array(config.rules.dropFirst()), [web, source, folder])
        XCTAssertEqual(try route(files[0], config, source: "sender"), .open(files[0], chrome, privateWindow: false))
        let page = URL(string: "https://example.com/report.html")!
        XCTAssertEqual(try route(page, config), .open(page, safari, privateWindow: false))
        try config.remember(url: page, destinationID: chrome.id)
        XCTAssertEqual(config.rules.filter(\.localFilesOnly).count, 3)
    }

    func testInvalidRememberAttemptDoesNotMutateConfiguration() throws {
        var config = Configuration()
        try config.remember(url: files[0], destinationID: chrome.id)
        let original = config
        XCTAssertThrowsError(try config.remember(url: URL(string: "mailto:example@example.com")!, destinationID: safari.id))
        XCTAssertEqual(config, original)
        XCTAssertThrowsError(try config.remember(url: files[0], destinationID: ""))
        XCTAssertEqual(config, original)
        XCTAssertThrowsError(try config.remember(url: URL(string: "https://example.com")!, destinationID: ""))
        XCTAssertEqual(config, original)
    }

    func testLegacySettingsMigrateWithoutChangingRuleBehavior() throws {
        var old = Configuration()
        old.defaultDestinationID = safari.id
        old.rules = [Rule(domain: "example.com", destinationID: chrome.id), Rule(sourceBundleID: "sender", destinationID: chrome.id)]
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        data["version"] = 1
        data["rules"] = try XCTUnwrap(data["rules"] as? [[String: Any]]).map { $0.filter { $0.key != "localFilesOnly" } }
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: data))
        XCTAssertEqual(decoded, old)
        XCTAssertEqual(decoded.version, 2)
        XCTAssertFalse(decoded.rules.contains(where: \.localFilesOnly))
        XCTAssertEqual(try route(files[0], decoded, source: "sender"), .open(files[0], chrome, privateWindow: false))
        XCTAssertEqual(try route(URL(string: "https://example.com")!, decoded), .open(URL(string: "https://example.com")!, chrome, privateWindow: false))
    }

    func testFileRulePersistsAndMarksTheNewSchema() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = SettingsRepository(url: folder.appendingPathComponent("settings.json"))
        var config = Configuration()
        try config.remember(url: files[0], destinationID: chrome.id, privateWindow: true)
        try repository.save(config)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: repository.url)) as? [String: Any])
        XCTAssertEqual(raw["version"] as? Int, 2)
        let restored = try repository.load().configuration
        XCTAssertEqual(restored, config)
        XCTAssertEqual(try route(files[2], restored), .open(files[2], chrome, privateWindow: true))
    }
}
