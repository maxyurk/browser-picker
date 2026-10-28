import XCTest
@testable import PickerCore

final class DomainPatternTests: XCTestCase {
    private let browser = Destination(id: "browser", name: "Browser", bundleID: "test.browser", appPath: "/Applications/Browser.app")

    func testWildcardMatchesSubdomainsAtAnyDepth() throws {
        let rule = try Rule(domain: "*.github.io", destinationID: browser.id).validated()
        for text in ["https://max.github.io", "http://docs.max.github.io/a", "https://MAX.GITHUB.IO.:8443/path?q=1#part"] {
            XCTAssertTrue(rule.matches(URL(string: text)!, source: nil), text)
        }
    }

    func testWildcardExcludesBareHostnameAndLookalikes() throws {
        let rule = try Rule(domain: "*.github.io").validated()
        for text in ["https://github.io", "https://github.io.", "https://notgithub.io", "https://github.io.evil.example", "https://max.github-io", "https://example.com/github.io", "https://github.io@evil.example/"] {
            XCTAssertFalse(rule.matches(URL(string: text)!, source: nil), text)
        }
    }

    func testWildcardNormalizesCaseWhitespaceAndTrailingDot() throws {
        let rule = try Rule(domain: "  *.GITHUB.IO. \n", includeSubdomains: false).validated()
        XCTAssertEqual(rule.domain, "*.github.io")
        XCTAssertTrue(rule.includeSubdomains)
        XCTAssertTrue(rule.matches(URL(string: "https://docs.max.github.io")!, source: nil))
        XCTAssertFalse(rule.matches(URL(string: "https://github.io")!, source: nil))
    }

    func testInternationalWildcardUsesNormalizedHostname() throws {
        let rule = try Rule(domain: "*.bücher.de").validated()
        XCTAssertEqual(rule.domain, "*.xn--bcher-kva.de")
        XCTAssertTrue(rule.matches(URL(string: "https://shop.bücher.de")!, source: nil))
        XCTAssertTrue(rule.matches(URL(string: "https://shop.xn--bcher-kva.de")!, source: nil))
        XCTAssertFalse(rule.matches(URL(string: "https://bücher.de")!, source: nil))
    }

    func testMalformedOrUnsupportedWildcardsAreRejected() {
        for pattern in ["*", "*.", "**.github.io", "foo.*.github.io", "github.*", "git*hub.io", "*.github.io/path", "*.github.io:443", "*.https://github.io", "*.github..io", "*.[::1]", "*.github.io?x=1", "*.github.io#part"] {
            XCTAssertThrowsError(try Rule(domain: pattern).validated(), pattern)
        }
        // Actual host normalization and remembered hosts remain strict.
        XCTAssertThrowsError(try WebURL.normalizeDomain("*.github.io"))
    }

    func testWildcardCombinesWithSourcePathAndEnabledConditions() throws {
        var rule = try Rule(domain: "*.github.io", pathPrefix: "/work/", sourceBundleID: "sender").validated()
        let url = URL(string: "https://max.github.io/work/report")!
        XCTAssertTrue(rule.matches(url, source: "sender"))
        XCTAssertFalse(rule.matches(url, source: "other"))
        XCTAssertFalse(rule.matches(URL(string: "https://max.github.io/personal")!, source: "sender"))
        rule.enabled = false
        XCTAssertFalse(rule.matches(url, source: "sender"))
    }

    func testWildcardNeverMatchesFileAuthority() throws {
        let file = URL(string: "file://max.github.io/tmp/report.html")!
        var configuration = Configuration()
        configuration.rules = [try Rule(domain: "*.github.io", destinationID: browser.id).validated()]
        XCTAssertFalse(configuration.rules[0].matches(file, source: nil))
        XCTAssertEqual(try Router.route(LinkRequest(url: file), configuration: configuration, destinations: [browser]), .prompt(file))
    }

    func testRoutingRetainsOrderAndForcedPicker() throws {
        let url = URL(string: "https://max.github.io/project")!
        var configuration = Configuration()
        configuration.rules = [try Rule(domain: "*.github.io").validated(), Rule(domain: "max.github.io", destinationID: browser.id)]
        XCTAssertEqual(try Router.route(LinkRequest(url: url), configuration: configuration, destinations: [browser]), .prompt(url))
        configuration.rules.reverse()
        XCTAssertEqual(try Router.route(LinkRequest(url: url), configuration: configuration, destinations: [browser]), .open(url, browser, privateWindow: false))
        XCTAssertEqual(try Router.route(LinkRequest(url: url, forcePrompt: true), configuration: configuration, destinations: [browser]), .prompt(url))
    }

    func testRememberedHostOverridesWildcardWithoutChangingSiblings() throws {
        let url = URL(string: "https://max.github.io/project")!
        var configuration = Configuration()
        configuration.rules = [try Rule(domain: "*.github.io", destinationID: browser.id).validated()]
        try configuration.remember(url: url, destinationID: "prompt")
        XCTAssertEqual(configuration.rules.count, 2)
        XCTAssertEqual(configuration.rules[1].domain, "*.github.io")
        XCTAssertEqual(try Router.route(LinkRequest(url: url), configuration: configuration, destinations: [browser]), .prompt(url))
        let sibling = URL(string: "https://other.github.io")!
        XCTAssertEqual(try Router.route(LinkRequest(url: sibling), configuration: configuration, destinations: [browser]), .open(sibling, browser, privateWindow: false))
        let previous = configuration
        XCTAssertThrowsError(try configuration.remember(domain: "*.github.io", destinationID: browser.id))
        XCTAssertEqual(configuration, previous)
    }

    func testWildcardRoundTripsAndOlderSchemasMigrate() throws {
        var configuration = Configuration()
        configuration.rules = [try Rule(domain: "*.github.io", destinationID: browser.id).validated()]
        let encoded = try JSONEncoder().encode(configuration)
        XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: encoded), configuration)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(raw["version"] as? Int, 3)
        for version in [1, 2] {
            var legacy = Configuration()
            legacy.rules = [Rule(domain: "example.com", includeSubdomains: false)]
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
            object["version"] = version
            let restored = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(restored, legacy)
            XCTAssertTrue(restored.rules[0].matches(URL(string: "https://example.com")!, source: nil))
            XCTAssertFalse(restored.rules[0].matches(URL(string: "https://sub.example.com")!, source: nil))
        }
    }
}
