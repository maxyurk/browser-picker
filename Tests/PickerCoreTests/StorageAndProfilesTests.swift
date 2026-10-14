import XCTest
@testable import PickerCore

final class StorageAndProfilesTests: XCTestCase {
    func withRepository(_ run: (SettingsRepository) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try run(SettingsRepository(url: root.appendingPathComponent("nested/settings.json")))
    }
    func testMissingSettingsUseDefaults() throws {
        try withRepository { repo in XCTAssertEqual(try repo.load().configuration, Configuration()) }
    }
    func testRoundTrip() throws {
        try withRepository { repo in
            var config = Configuration(); config.defaultDestinationID = "chrome:Profile 2"
            config.rules = [try Rule(domain: "example.com", destinationID: "chrome", privateWindow: true).validated()]
            config.hiddenDestinationIDs = ["safari"]; config.cleanTracking = true
            try repo.save(config)
            XCTAssertEqual(try repo.load().configuration, config)
            XCTAssertFalse(try repo.load().recoveredFromBackup)
        }
    }
    func testBackupRecoveryAndDamagedFilePreserved() throws {
        try withRepository { repo in
            var config = Configuration(); try repo.save(config)
            config.defaultDestinationID = "chrome"; try repo.save(config)
            try Data("not json".utf8).write(to: repo.url)
            XCTAssertTrue(try repo.load().recoveredFromBackup)
            XCTAssertEqual(try repo.load().configuration.defaultDestinationID, "prompt")
            try repo.save(config)
            let files = try FileManager.default.contentsOfDirectory(atPath: repo.url.deletingLastPathComponent().path)
            XCTAssertTrue(files.contains { $0.hasPrefix("settings.json.damaged-") })
            XCTAssertEqual(try repo.load().configuration, config)
        }
    }
    func testCorruptSettingsWithoutBackupThrowAndRemainUntouched() throws {
        try withRepository { repo in
            try FileManager.default.createDirectory(at: repo.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let broken = Data("{".utf8); try broken.write(to: repo.url)
            XCTAssertThrowsError(try repo.load()); XCTAssertEqual(try Data(contentsOf: repo.url), broken)
        }
    }
    func testFutureSchemaNotDowngraded() throws {
        try withRepository { repo in
            try repo.save(Configuration()); try repo.save(Configuration())
            try Data("{\"version\":99}".utf8).write(to: repo.url)
            XCTAssertThrowsError(try repo.load()) { XCTAssertEqual($0 as? PickerError, .unsupportedVersion(99)) }
        }
    }
    func testAbsentOptionalKeysUseDefaults() throws {
        let config = try JSONDecoder().decode(Configuration.self, from: Data("{}".utf8))
        XCTAssertEqual(config, Configuration())
    }
    func testOutsideClickDismissalDefaultsOnForOlderSettings() throws {
        let config = try JSONDecoder().decode(Configuration.self, from: Data(#"{"version":1,"defaultDestinationID":"chrome","cleanTracking":true}"#.utf8))
        XCTAssertTrue(config.dismissPickerOnOutsideClick)
        XCTAssertEqual(config.defaultDestinationID, "chrome"); XCTAssertTrue(config.cleanTracking)
    }
    func testOutsideClickDismissalCanBeDisabledAndPersisted() throws {
        try withRepository { repo in
            var config = Configuration(); config.dismissPickerOnOutsideClick = false
            try repo.save(config)
            XCTAssertFalse(try repo.load().configuration.dismissPickerOnOutsideClick)
            config.dismissPickerOnOutsideClick = true; try repo.save(config)
            XCTAssertTrue(try repo.load().configuration.dismissPickerOnOutsideClick)
        }
    }
    func testInvalidAndDuplicateRulesRejected() throws {
        var config = Configuration(); config.rules = [Rule()]
        XCTAssertThrowsError(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config)))
        let rule = Rule(domain: "a.com"); config.rules = [rule, rule]
        XCTAssertThrowsError(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config)))
    }
    func testFailedSaveDoesNotOverwrite() throws {
        try withRepository { repo in
            try repo.save(Configuration()); let original = try Data(contentsOf: repo.url)
            var config = Configuration(); config.rules = [Rule()]
            XCTAssertThrowsError(try repo.save(config)); XCTAssertEqual(try Data(contentsOf: repo.url), original)
        }
    }
    func testManySavesAlwaysDecode() throws {
        try withRepository { repo in
            for i in 0..<100 {
                var config = Configuration(); config.defaultDestinationID = "browser-\(i)"
                try repo.save(config); XCTAssertEqual(try repo.load().configuration, config)
            }
        }
    }
    func testQueueEmpty() { var queue = RequestQueue(); XCTAssertEqual(queue.count, 0); XCTAssertNil(queue.pop()) }
    func testQueueKeepsDuplicatesAndOrder() {
        var queue = RequestQueue(); let request = LinkRequest(url: URL(string: "https://example.com")!)
        queue.append(request); queue.append(request); XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.pop(), request); XCTAssertEqual(queue.pop(), request); XCTAssertNil(queue.pop())
    }
    func testQueueCompactionAndInterleaving() {
        var queue = RequestQueue()
        for i in 0..<5_000 { queue.append(LinkRequest(url: URL(string: "https://a.com/\(i)")!)) }
        for i in 0..<4_000 { XCTAssertEqual(queue.pop()?.url.path, "/\(i)") }
        for i in 5_000..<6_000 { queue.append(LinkRequest(url: URL(string: "https://a.com/\(i)")!)) }
        XCTAssertEqual(queue.count, 2_000)
        for i in 4_000..<6_000 { XCTAssertEqual(queue.pop()?.url.path, "/\(i)") }
        XCTAssertNil(queue.pop()); XCTAssertEqual(queue.count, 0)
        queue.append(LinkRequest(url: URL(string: "https://a.com/reuse")!)); XCTAssertEqual(queue.pop()?.url.path, "/reuse")
    }
    func testChromeProfileParsing() {
        let input = Data(#"{"profile":{"info_cache":{"Profile 10":{"name":"Work"},"Default":{"name":"Personal"},"Profile 2":{"name":""},"../evil":{"name":"Bad"}}}}"#.utf8)
        XCTAssertEqual(ChromeProfiles.read(input).map(\.directory), ["Default", "Profile 2", "Profile 10"])
        XCTAssertEqual(ChromeProfiles.read(input).map(\.name), ["Personal", "Profile 2", "Work"])
    }
    func testMalformedChromeState() {
        for input in ["", "no json", "[]", "null", "{}", #"{"profile":{"info_cache":[]}}"#] { XCTAssertTrue(ChromeProfiles.read(Data(input.utf8)).isEmpty) }
    }
    func testChromeProfileDirectoryValidation() {
        for directory in ["Default", "Profile 0", "Profile 2", "Profile 100"] { XCTAssertTrue(ChromeProfiles.validDirectory(directory)) }
        for directory in ["", "Profile ", "Profile -1", "Profile 2/../", "../Default", "--incognito", "Profile １", "Default/", "Profile 2\n"] { XCTAssertFalse(ChromeProfiles.validDirectory(directory), directory) }
    }
    func testChromeArgumentsPreserveURLAsOneArgument() throws {
        let url = URL(string: "https://a.com/?x=$(touch%20/tmp/evil)&x=%22%3B&x=--flag")!
        XCTAssertEqual(try ChromeProfiles.arguments(url: url, profile: "Profile 2", privateWindow: true), ["--profile-directory=Profile 2", "--incognito", url.absoluteString])
        XCTAssertEqual(try ChromeProfiles.arguments(url: url, profile: nil, privateWindow: false), [url.absoluteString])
        XCTAssertThrowsError(try ChromeProfiles.arguments(url: url, profile: "../evil", privateWindow: false))
        XCTAssertEqual(try ChromeProfiles.arguments(url: URL(string: "file:///a")!, profile: nil, privateWindow: false), ["file:///a"])
    }
}
