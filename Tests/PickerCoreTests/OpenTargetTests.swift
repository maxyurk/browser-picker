import XCTest
@testable import PickerCore

final class OpenTargetTests: XCTestCase {
    private let browser = Destination(id: "browser", name: "Browser", bundleID: "example.browser", appPath: "/Applications/Browser.app", supportsPrivate: true)

    func testFileURLsOfAnyTypeAreAccepted() throws {
        for text in ["file:///tmp/report.html", "file:///tmp/no-extension", "file:///tmp/unknown.xyz", "file:///tmp/missing.pdf", "file:///tmp/folder/", "file://localhost/tmp/report.html", "file://server/share/report.html"] {
            XCTAssertEqual(try OpenTarget.parse(text), URL(string: text), text)
        }
    }

    func testFilePathsPreserveSpecialCharactersAndWhitespace() throws {
        for path in ["/tmp/report with spaces.html", "/tmp/日本語 #1?100%+test.html", "/tmp/literal%20name.html", "/tmp/a\nb\tc.html", "/tmp/space at end "] {
            let result = try OpenTarget.parse(path, allowBareHost: true)
            XCTAssertTrue(result.isFileURL)
            XCTAssertEqual(result.path, path)
        }
    }

    func testRelativeAndHomePaths() throws {
        XCTAssertEqual(try OpenTarget.parse("./missing report.html"), URL(fileURLWithPath: "./missing report.html"))
        XCTAssertEqual(try OpenTarget.parse("../missing.html"), URL(fileURLWithPath: "../missing.html"))
        XCTAssertEqual(try OpenTarget.parse("~/missing report.html"), URL(fileURLWithPath: NSHomeDirectory() + "/missing report.html"))
    }

    func testFileProcessingNeverCleansOrUnwraps() throws {
        for text in ["file:///tmp/report%20%23%25%2B.html?utm_source=x&fbclid=1#section", "file://google.com/url?q=https%3A%2F%2Fexample.com&url=https%3A%2F%2Fother.com"] {
            let file = try XCTUnwrap(URL(string: text))
            for unwrap in [false, true] {
                for clean in [false, true] { XCTAssertEqual(try OpenTarget.process(file, unwrap: unwrap, cleanTracking: clean), file) }
            }
        }
    }

    func testWebLinkBehaviorIsPreserved() throws {
        XCTAssertEqual(try OpenTarget.parse("example.com", allowBareHost: true).absoluteString, "https://example.com")
        let web = URL(string: "https://example.com/?utm_source=x&keep=%2f#section")!
        XCTAssertEqual(try OpenTarget.process(web, unwrap: true, cleanTracking: true).absoluteString, "https://example.com/?keep=%2f#section")
        for input in ["", "hello world", "javascript:alert(1)", "mailto:example@example.com"] {
            XCTAssertThrowsError(try OpenTarget.parse(input))
        }
    }

    func testFileUsesPickerOrConfiguredDefault() throws {
        let file = URL(fileURLWithPath: "/tmp/not-an-html-file.xyz")
        var config = Configuration(); config.cleanTracking = true
        XCTAssertEqual(try Router.route(LinkRequest(url: file), configuration: config, destinations: [browser]), .prompt(file))
        config.defaultDestinationID = browser.id
        XCTAssertEqual(try Router.route(LinkRequest(url: file), configuration: config, destinations: [browser]), .open(file, browser, privateWindow: false))
        XCTAssertEqual(try Router.route(LinkRequest(url: file, forcePrompt: true), configuration: config, destinations: [browser]), .prompt(file))
    }

    func testWebsiteRulesCannotMatchFileAuthority() throws {
        let file = URL(string: "file://example.com/tmp/report.html")!
        var config = Configuration(); config.rules = [Rule(domain: "example.com", destinationID: browser.id)]
        XCTAssertFalse(config.rules[0].matches(file, source: nil))
        XCTAssertEqual(try Router.route(LinkRequest(url: file), configuration: config, destinations: [browser]), .prompt(file))
    }

    func testSourceAppRulesCanRouteFiles() throws {
        let file = URL(fileURLWithPath: "/tmp/report.html")
        var config = Configuration()
        config.rules = [Rule(pathPrefix: "/tmp/", sourceBundleID: "example.sender", destinationID: browser.id, privateWindow: true)]
        XCTAssertTrue(config.rules[0].matches(file, source: "example.sender"))
        XCTAssertEqual(try Router.route(LinkRequest(url: file, sourceBundleID: "example.sender"), configuration: config, destinations: [browser]), .open(file, browser, privateWindow: true))
        XCTAssertEqual(try Router.route(LinkRequest(url: file, sourceBundleID: "other.sender"), configuration: config, destinations: [browser]), .prompt(file))
    }

    func testMissingBrowserStillPromptsForFile() throws {
        let file = URL(fileURLWithPath: "/tmp/report.html")
        var config = Configuration(); config.defaultDestinationID = "missing"
        XCTAssertEqual(try Router.route(LinkRequest(url: file), configuration: config, destinations: [browser]), .prompt(file))
    }

    func testProfileAndPrivateArgumentsPreserveFileAddress() throws {
        let file = URL(fileURLWithPath: "/tmp/literal%20 #日本語+?.html")
        XCTAssertEqual(try ChromeProfiles.arguments(url: file, profile: "Profile 2", privateWindow: true), ["--profile-directory=Profile 2", "--incognito", file.absoluteString])
        XCTAssertEqual(try ChromeProfiles.arguments(url: file, profile: nil, privateWindow: false), [file.absoluteString])
    }
}
