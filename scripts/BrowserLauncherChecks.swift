// Headless regression checks: no NSApplication, browser launch, or desktop UI.
import AppKit
import PickerCore

@MainActor
private final class BackgroundWorkspace: BrowserWorkspaceOpening {
    var error: NSError?
    var requestCount = 0
    var lastURLs: [URL] = []
    var lastFileAddress: String?
    var activates = true
    var allowsSubstitution = true
    func open(_ urls: [URL], withApplicationAt appURL: URL, configuration: NSWorkspace.OpenConfiguration, completionHandler: @escaping BrowserOpenCompletion) {
        lastURLs = urls; lastFileAddress = nil
        finish(configuration, completionHandler)
    }
    func openApplication(at appURL: URL, configuration: NSWorkspace.OpenConfiguration, completionHandler: @escaping BrowserOpenCompletion) {
        lastURLs = []
        lastFileAddress = configuration.appleEvent?.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue
        finish(configuration, completionHandler)
    }
    private func finish(_ configuration: NSWorkspace.OpenConfiguration, _ completion: @escaping BrowserOpenCompletion) {
        requestCount += 1; activates = configuration.activates
        allowsSubstitution = configuration.allowsRunningApplicationSubstitution
        let failure = error
        DispatchQueue.global(qos: .userInitiated).async {
            dispatchPrecondition(condition: .notOnQueue(.main))
            completion(nil, failure)
        }
    }
}

@main
@MainActor
enum BrowserLauncherChecks {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("browser-picker-callback-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Fixture.app")
        let executable = bundle.appendingPathComponent("Contents/MacOS/Fixture")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let plist: [String: Any] = ["CFBundleIdentifier": "test.browser-picker.callback", "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        let destination = Destination(id: "fixture", name: "Fixture", bundleID: "test.browser-picker.callback", appPath: bundle.path)
        let workspace = BackgroundWorkspace()
        let launcher = BrowserLauncher(workspace: workspace)
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            checks += 1
            guard value else { fatalError(message) }
        }
        func launch(_ url: URL, background: Bool = false) async -> Error? {
            await withCheckedContinuation { continuation in
                launcher.open(url, in: destination, privateWindow: false, background: background) { error in
                    MainActor.preconditionIsolated()
                    continuation.resume(returning: error)
                }
            }
        }
        let repository = SettingsRepository(url: root.appendingPathComponent("settings.json"))
        let targets = [URL(string: "https://example.com/remember")!, URL(fileURLWithPath: "/tmp/report #日本語 %.html")]
        for target in targets {
            workspace.error = nil
            var configuration = Configuration()
            let result = await launch(target)
            check(result == nil, "Background success must reach the main actor without crashing")
            try configuration.remember(url: target, destinationID: destination.id)
            try repository.save(configuration)
            let saved = try repository.load().configuration
            let next = target.isFileURL ? URL(fileURLWithPath: "/another/folder/new.pdf") : URL(string: "https://example.com/again")!
            check(try Router.route(LinkRequest(url: next), configuration: saved, destinations: [destination]) == .open(next, destination, privateWindow: false), "Remembered choice must survive the asynchronous callback and reload")
            check(target.isFileURL ? workspace.lastFileAddress == target.absoluteString : workspace.lastURLs == [target], "The exact link or file address must reach the opener")
            check(!workspace.allowsSubstitution, "Opening must not substitute a different browser copy")
            workspace.error = NSError(domain: "BrowserLauncherChecks", code: 42, userInfo: [NSLocalizedDescriptionKey: "Expected failure"])
            let before = try Data(contentsOf: repository.url)
            let failure = await launch(target, background: true) as NSError?
            check(failure?.domain == "BrowserLauncherChecks" && failure?.code == 42, "Background errors must reach the main actor unchanged")
            check(!workspace.activates, "Background opening must remain in the background")
            check(try Data(contentsOf: repository.url) == before, "Failed opening must leave saved settings unchanged")
        }
        workspace.error = nil
        for index in 0..<100 {
            check(await launch(URL(string: "https://example.com/burst/\(index)")!) == nil, "Repeated background callbacks must remain safe")
        }
        check(workspace.requestCount == 104, "Each launch must call the workspace exactly once")
        print("Browser launcher callback checks: \(checks) passed; no browser or desktop UI opened.")
    }
}
