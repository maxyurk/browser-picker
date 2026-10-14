import XCTest
@testable import PickerCore

final class DefaultBrowserSetupTests: XCTestCase {
    @MainActor func testAlreadyActiveDoesNotAskAgain() async {
        var requests: [String] = []
        let result = await DefaultBrowserSetup.activate(bundleID: "picker", handler: { _ in "picker" }) { requests.append($0) }
        XCTAssertEqual(result, .active); XCTAssertTrue(requests.isEmpty)
    }
    @MainActor func testSettingHttpAlsoChangesHttpsAndSkipsRedundantRequest() async {
        var handlers = ["http": "safari", "https": "safari"]
        var requests: [String] = []
        let result = await DefaultBrowserSetup.activate(bundleID: "picker", handler: { handlers[$0] }) { scheme in
            requests.append(scheme)
            handlers["http"] = "picker"; handlers["https"] = "picker"
        }
        XCTAssertEqual(result, .active); XCTAssertEqual(requests, ["http"])
    }
    @MainActor func testSystemErrorAfterSuccessfulChangeDoesNotProduceFalseWarning() async {
        var handlers = ["http": "safari", "https": "safari"]
        let result = await DefaultBrowserSetup.activate(bundleID: "picker", handler: { handlers[$0] }) { _ in
            handlers["http"] = "picker"; handlers["https"] = "picker"
            throw NSError(domain: NSCocoaErrorDomain, code: 256)
        }
        XCTAssertEqual(result, .active)
    }
    @MainActor func testFailureWithUnchangedHandlersOffersSystemSettings() async {
        let result = await DefaultBrowserSetup.activate(bundleID: "picker", handler: { _ in "safari" }) { _ in
            throw NSError(domain: NSCocoaErrorDomain, code: 256)
        }
        XCTAssertEqual(result, .needsSystemSettings(errorDomain: NSCocoaErrorDomain, errorCode: 256))
    }
    @MainActor func testPartialChangeDoesNotClaimSuccess() async {
        var handlers = ["http": "safari", "https": "safari"]
        let result = await DefaultBrowserSetup.activate(bundleID: "picker", handler: { handlers[$0] }) { scheme in
            if scheme == "http" { handlers[scheme] = "picker" }
            else { throw NSError(domain: NSCocoaErrorDomain, code: 256) }
        }
        XCTAssertEqual(result, .needsSystemSettings(errorDomain: NSCocoaErrorDomain, errorCode: 256))
    }
    @MainActor func testNoOpSetterDoesNotClaimSuccess() async {
        let result = await DefaultBrowserSetup.activate(bundleID: "picker", handler: { _ in "safari" }) { _ in }
        XCTAssertEqual(result, .needsSystemSettings(errorDomain: nil, errorCode: nil))
    }
    @MainActor func testSeparateSchemeUpdates() async {
        var handlers = ["http": "safari", "https": "safari"]
        var requests: [String] = []
        let result = await DefaultBrowserSetup.activate(bundleID: "picker", handler: { handlers[$0] }) { scheme in
            requests.append(scheme); handlers[scheme] = "picker"
        }
        XCTAssertEqual(result, .active); XCTAssertEqual(requests, ["http", "https"])
    }
    @MainActor func testCaseInsensitiveIdentifiersAndMissingHandlers() async {
        XCTAssertTrue(DefaultBrowserSetup.isActive(bundleID: "Local.Example.Picker", handler: { _ in "local.example.picker" }))
        XCTAssertFalse(DefaultBrowserSetup.isActive(bundleID: "picker", handler: { _ in nil }))
        XCTAssertFalse(DefaultBrowserSetup.isActive(bundleID: "picker", handler: { $0 == "http" ? "picker" : "safari" }))
        let result = await DefaultBrowserSetup.activate(bundleID: "", handler: { _ in nil }) { _ in XCTFail("Should not call setter for missing identity") }
        XCTAssertEqual(result, .needsSystemSettings(errorDomain: nil, errorCode: nil))
    }
}
