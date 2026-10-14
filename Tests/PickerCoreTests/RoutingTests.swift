import XCTest
@testable import PickerCore

final class RoutingTests: XCTestCase {
    let safari = Destination(id: "safari", name: "Safari", bundleID: "com.apple.Safari", appPath: "/Applications/Safari.app")
    let chrome = Destination(id: "chrome", name: "Chrome", bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", supportsPrivate: true)
    let url = URL(string: "https://team.example.com/work/project")!
    func route(_ config: Configuration, source: String? = nil, force: Bool = false, url: URL? = nil) throws -> Route {
        try Router.route(LinkRequest(url: url ?? self.url, sourceBundleID: source, forcePrompt: force), configuration: config, destinations: [safari, chrome])
    }
    func testDefaultPrompt() throws { XCTAssertEqual(try route(Configuration()), .prompt(url)) }
    func testDefaultBrowser() throws {
        var config = Configuration(); config.defaultDestinationID = "safari"
        XCTAssertEqual(try route(config), .open(url, safari, privateWindow: false))
    }
    func testForcedPromptOverridesRulesAndDefault() throws {
        var config = Configuration(); config.defaultDestinationID = "safari"; config.rules = [Rule(domain: "example.com", destinationID: "chrome")]
        XCTAssertEqual(try route(config, force: true), .prompt(url))
    }
    func testDomainIncludesSubdomains() throws {
        var config = Configuration(); config.rules = [Rule(domain: "example.com", destinationID: "chrome")]
        XCTAssertEqual(try route(config), .open(url, chrome, privateWindow: false))
    }
    func testExactDomain() throws {
        var config = Configuration(); config.rules = [Rule(domain: "example.com", includeSubdomains: false, destinationID: "chrome")]
        XCTAssertEqual(try route(config), .prompt(url))
        XCTAssertEqual(try route(config, url: URL(string: "https://example.com")!), .open(URL(string: "https://example.com")!, chrome, privateWindow: false))
    }
    func testDomainBoundaryAndLookalikes() {
        let rule = Rule(domain: "example.com")
        for input in ["https://notexample.com", "https://example.com.evil.org", "https://example-com.org", "https://evil.org/example.com"] {
            XCTAssertFalse(rule.matches(URL(string: input)!, source: nil), input)
        }
    }
    func testTrailingDotAndCase() {
        XCTAssertTrue(Rule(domain: "example.com").matches(URL(string: "https://EXAMPLE.COM./")!, source: nil))
    }
    func testSourceOnlyRule() throws {
        var config = Configuration(); config.rules = [Rule(sourceBundleID: "com.tinyspeck.slackmacgap", destinationID: "chrome")]
        XCTAssertEqual(try route(config, source: "com.tinyspeck.slackmacgap"), .open(url, chrome, privateWindow: false))
        XCTAssertEqual(try route(config, source: "com.apple.Mail"), .prompt(url))
        XCTAssertEqual(try route(config), .prompt(url))
    }
    func testDomainAndSourceAreAndConditions() throws {
        let rule = Rule(domain: "example.com", sourceBundleID: "slack", destinationID: "chrome")
        XCTAssertTrue(rule.matches(url, source: "slack"))
        XCTAssertFalse(rule.matches(URL(string: "https://other.com")!, source: "slack"))
        XCTAssertFalse(rule.matches(url, source: "mail"))
    }
    func testPathPrefix() {
        let rule = Rule(domain: "example.com", pathPrefix: "/work")
        XCTAssertTrue(rule.matches(url, source: nil))
        XCTAssertTrue(rule.matches(URL(string: "https://example.com/workspace")!, source: nil))
        XCTAssertFalse(rule.matches(URL(string: "https://example.com/Work")!, source: nil))
        XCTAssertFalse(rule.matches(URL(string: "https://example.com/?path=/work")!, source: nil))
    }
    func testFirstRuleWins() throws {
        var config = Configuration(); config.rules = [Rule(domain: "example.com", destinationID: "chrome"), Rule(domain: "example.com", destinationID: "safari")]
        XCTAssertEqual(try route(config), .open(url, chrome, privateWindow: false))
    }
    func testDisabledRuleSkipped() throws {
        var config = Configuration(); config.rules = [Rule(domain: "example.com", destinationID: "chrome", enabled: false), Rule(domain: "example.com", destinationID: "safari")]
        XCTAssertEqual(try route(config), .open(url, safari, privateWindow: false))
    }
    func testExplicitPromptRuleOverridesDefault() throws {
        var config = Configuration(); config.defaultDestinationID = "safari"; config.rules = [Rule(domain: "example.com")]
        XCTAssertEqual(try route(config), .prompt(url))
    }
    func testMissingDefaultFallsBackToPicker() throws {
        var config = Configuration(); config.defaultDestinationID = "uninstalled"
        XCTAssertEqual(try route(config), .prompt(url))
    }
    func testMissingRuleTargetDoesNotFallThroughToAnotherAccount() throws {
        var config = Configuration(); config.defaultDestinationID = "safari"
        config.rules = [Rule(domain: "example.com", destinationID: "missing-profile"), Rule(domain: "example.com", destinationID: "chrome")]
        XCTAssertEqual(try route(config), .prompt(url))
    }
    func testHiddenBrowserCanStillBeRuleTarget() throws {
        var config = Configuration(); config.hiddenDestinationIDs = ["chrome"]; config.rules = [Rule(domain: "example.com", destinationID: "chrome")]
        XCTAssertEqual(try route(config), .open(url, chrome, privateWindow: false))
    }
    func testPrivateRoute() throws {
        var config = Configuration(); config.rules = [Rule(domain: "example.com", destinationID: "chrome", privateWindow: true)]
        XCTAssertEqual(try route(config), .open(url, chrome, privateWindow: true))
    }
    func testUnsupportedPrivateRouteFallsBack() throws {
        var config = Configuration(); config.rules = [Rule(domain: "example.com", destinationID: "safari", privateWindow: true)]
        XCTAssertEqual(try route(config), .prompt(url))
    }
    func testRedirectResolvedBeforeMatching() throws {
        var config = Configuration(); config.rules = [Rule(domain: "example.com", destinationID: "chrome")]
        let wrapper = URL(string: "https://google.com/url?q=https%3A%2F%2Fexample.com%2F")!
        XCTAssertEqual(try route(config, url: wrapper), .open(URL(string: "https://example.com/")!, chrome, privateWindow: false))
    }
    func testRememberReplacesGenericRuleAndKeepsSourceRule() throws {
        var config = Configuration()
        config.rules = [Rule(domain: "example.com", destinationID: "safari"), Rule(domain: "example.com", sourceBundleID: "slack", destinationID: "chrome"), Rule(domain: "example.com", pathPrefix: "/team", destinationID: "chrome")]
        try config.remember(domain: "EXAMPLE.COM", destinationID: "chrome", privateWindow: true)
        XCTAssertEqual(config.rules.count, 3)
        XCTAssertEqual(config.rules[0].destinationID, "chrome"); XCTAssertTrue(config.rules[0].privateWindow)
        XCTAssertEqual(config.rules[1].sourceBundleID, "slack")
    }
    func testRememberInvalidDomainDoesNotMutate() {
        var config = Configuration(); let before = config
        XCTAssertThrowsError(try config.remember(domain: "https://example.com", destinationID: "chrome"))
        XCTAssertEqual(config, before)
    }
    func testRuleValidation() throws {
        XCTAssertEqual(try Rule(domain: " EXAMPLE.COM ", sourceBundleID: " slack ").validated().domain, "example.com")
        XCTAssertEqual(try Rule(sourceBundleID: " slack ").validated().sourceBundleID, "slack")
        XCTAssertThrowsError(try Rule().validated())
        XCTAssertThrowsError(try Rule(domain: "a.com", pathPrefix: "path").validated())
        XCTAssertThrowsError(try Rule(domain: "a.com", destinationID: "").validated())
    }
    func testInvalidSchemeRejected() {
        XCTAssertThrowsError(try route(Configuration(), url: URL(string: "file:///etc/passwd")!))
    }
    func testInternationalDomainRule() throws {
        let rule = try Rule(domain: "bücher.de").validated()
        XCTAssertTrue(rule.matches(URL(string: "https://bücher.de/a")!, source: nil))
    }
    func testIPv6RuleMatchesEquivalentAddresses() throws {
        let rule = try Rule(domain: "[0:0:0:0:0:0:0:1]").validated()
        XCTAssertTrue(rule.matches(URL(string: "http://[::1]:3000/work")!, source: nil))
        XCTAssertTrue(rule.matches(URL(string: "http://[0:0:0:0:0:0:0:1]/work")!, source: nil))
        XCTAssertFalse(rule.matches(URL(string: "http://[::2]/work")!, source: nil))
    }
    func testRememberIPv6Host() throws {
        var config = Configuration(); try config.remember(domain: "[::1]", destinationID: "chrome")
        let local = URL(string: "http://[::1]:3000/work")!
        XCTAssertEqual(try route(config, url: local), .open(local, chrome, privateWindow: false))
    }
    func testRoutingBenchmark() throws {
        var config = Configuration(); config.defaultDestinationID = "safari"
        config.rules = (0..<50).map { Rule(domain: "site\($0).example.com", destinationID: "chrome") }
        var timings: [Double] = []; timings.reserveCapacity(10_000)
        for _ in 0..<10_000 {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = try route(config)
            timings.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000)
        }
        timings.sort()
        print("BENCHMARK route with 50 rules: median \(timings[5_000]) µs, p95 \(timings[9_500]) µs, p99 \(timings[9_900]) µs")
        XCTAssertLessThan(timings[9_500], 2_000, "Routing should remain below 2ms even in a debug build")
    }
}
