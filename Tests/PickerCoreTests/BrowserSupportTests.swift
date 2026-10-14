import XCTest
@testable import PickerCore

final class BrowserSupportTests: XCTestCase {
    func testUnknownBrowserDiscoveredWithoutVendorAllowlist() {
        let info: [String: Any] = ["CFBundleIdentifier": "org.example.NewBrowser", "CFBundleDocumentTypes": [["CFBundleTypeRole": "Viewer", "LSItemContentTypes": ["public.html"]]]]
        XCTAssertTrue(BrowserSupport.isBrowser(info: info, registeredForWebURLs: true))
        XCTAssertFalse(BrowserSupport.isBrowser(info: info, registeredForWebURLs: false))
    }
    func testLegacyHTMLAndXHTMLMetadata() {
        for document: [String: Any] in [
            ["CFBundleTypeExtensions": ["HTM"], "CFBundleTypeRole": "Viewer"],
            ["CFBundleTypeMIMETypes": ["application/xhtml+xml"], "CFBundleTypeRole": "Editor"],
            ["LSItemContentTypes": ["public.xhtml"]]
        ] { XCTAssertTrue(BrowserSupport.isBrowser(info: ["CFBundleDocumentTypes": [document]], registeredForWebURLs: true)) }
    }
    func testForwardersAndNonBrowserHandlersExcluded() {
        XCTAssertFalse(BrowserSupport.isBrowser(info: ["CFBundleDocumentTypes": [["LSItemContentTypes": ["public.data"]]]], registeredForWebURLs: true))
        XCTAssertFalse(BrowserSupport.isBrowser(info: ["LSUIElement": true, "CFBundleDocumentTypes": [["LSItemContentTypes": ["public.html"]]]], registeredForWebURLs: true))
        XCTAssertFalse(BrowserSupport.isBrowser(info: ["CFBundleDocumentTypes": [["LSItemContentTypes": ["public.html"], "CFBundleTypeRole": "None"]]], registeredForWebURLs: true))
        XCTAssertFalse(BrowserSupport.isBrowser(info: ["CFBundleIdentifier": "com.googlecode.iterm2", "CFBundleDocumentTypes": [["LSItemContentTypes": ["public.html"]]]], registeredForWebURLs: true))
    }
    func testMalformedMetadataIsIgnored() {
        for value: Any in ["html", [], ["LSItemContentTypes": "public.html"], 42] {
            XCTAssertFalse(BrowserSupport.isBrowser(info: ["CFBundleDocumentTypes": value], registeredForWebURLs: true))
        }
    }
    func testChromiumRootsComeFromBrowserMetadata() {
        for path in ["Google/Chrome Beta", "Chromium", "BraveSoftware/Brave-Browser", "Microsoft Edge"] {
            XCTAssertEqual(BrowserSupport.chromiumDataSubdirectory(info: ["CrProductDirName": path], bundleID: "org.example.Browser"), path)
        }
    }
    func testProfileRootsCannotEscapeApplicationSupport() {
        for path in ["", "../secrets", "/etc", "Google/../Chrome", "Google//Chrome", "Google/./Chrome", "C:\\Chrome", "a\nb"] {
            XCTAssertNil(BrowserSupport.chromiumDataSubdirectory(info: ["CrProductDirName": path], bundleID: "com.google.Chrome"), path)
        }
    }
    func testUnknownBrowsersDoNotReceiveChromiumFlags() {
        XCTAssertNil(BrowserSupport.chromiumDataSubdirectory(info: [:], bundleID: "org.example.Browser"))
        XCTAssertEqual(BrowserSupport.chromiumDataSubdirectory(info: [:], bundleID: "com.google.Chrome"), "Google/Chrome")
    }
    func testNamesUseBundleMetadataAndFilenameFallback() {
        XCTAssertEqual(BrowserSupport.displayName(info: ["CFBundleDisplayName": "New Browser", "CFBundleName": "Internal"], fallback: "File"), "New Browser")
        XCTAssertEqual(BrowserSupport.displayName(info: ["CFBundleDisplayName": "  ", "CFBundleName": "Internal"], fallback: "File"), "Internal")
        XCTAssertEqual(BrowserSupport.displayName(info: [:], fallback: "Unusual Browser"), "Unusual Browser")
    }
    func testManualLocationsPersistAndOlderSettingsStillDecode() throws {
        var config = Configuration(); config.customBrowserPaths = ["/Applications/New Browser.app", "/Volumes/Apps/Browser.app"]
        XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config)).customBrowserPaths, config.customBrowserPaths)
        XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: Data(#"{"version":1}"#.utf8)).customBrowserPaths, [])
    }
    func testGenericBrowserRoutingAndRememberedChoice() throws {
        let browser = Destination(id: "org.example.NewBrowser", name: "New Browser", bundleID: "org.example.NewBrowser", appPath: "/Applications/New Browser.app")
        let url = URL(string: "https://example.com/page")!
        var config = Configuration()
        try config.remember(domain: "example.com", destinationID: browser.id)
        XCTAssertEqual(try Router.route(LinkRequest(url: url), configuration: config, destinations: [browser]), .open(url, browser, privateWindow: false))
        XCTAssertEqual(try Router.route(LinkRequest(url: url), configuration: config, destinations: []), .prompt(url))
    }
}
