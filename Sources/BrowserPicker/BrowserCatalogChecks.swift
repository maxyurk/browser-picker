import AppKit
import PickerCore

/// Native discovery and persistence regressions; never executes the fixture apps.
@MainActor
enum BrowserCatalogChecks {
    static func run(check: (Bool, String) -> Void) {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("PickerCatalog-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            func fixture(_ name: String, id: String, executable: String = "FixtureBrowser") throws -> URL {
                let app = temporary.appendingPathComponent(name + ".app")
                let directory = app.appendingPathComponent("Contents/MacOS")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleExecutable": executable, "CFBundlePackageType": "APPL"]
                try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
                let binary = directory.appendingPathComponent(executable)
                try Data().write(to: binary)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
                return app
            }
            let id = "example.fixture." + UUID().uuidString
            let first = try fixture("Unregistered Browser", id: id)
            let second = try fixture("Another Copy", id: id)
            let own = try fixture("Another Picker", id: "example.other-picker", executable: "BrowserPicker")
            check(BrowserCatalog.application(at: first) != nil, "unregistered browser app accepted for manual addition")
            check(BrowserCatalog.application(at: own) == nil, "manual addition cannot route back into another picker copy")
            check(BrowserCatalog.application(at: temporary) == nil, "manual addition rejects folders without an app bundle")
            let one = BrowserCatalog.discover(customPaths: [first.path]).filter { $0.bundleID == id }
            check(one.count == 1 && one[0].name == "Unregistered Browser", "unknown manually added browser has a named destination")
            let two = BrowserCatalog.discover(customPaths: [first.path, second.path]).filter { $0.bundleID == id }
            check(two.count == 1 && two[0].appPath == second.path, "multiple browser copies resolve to the chosen location without duplicate IDs")
            let store = AppStore(settingsURL: temporary.appendingPathComponent("settings.json"))
            store.addBrowser(first)
            check(store.configuration.customBrowserPaths == [first.path] && store.destinations.contains { $0.id == id }, "added browser persists and appears immediately")
            store.addBrowser(second)
            check(store.configuration.customBrowserPaths == [second.path] && store.destinations.first { $0.id == id }?.appPath == second.path, "adding another copy updates the stored location")
            let reloaded = AppStore(settingsURL: temporary.appendingPathComponent("settings.json"))
            check(reloaded.destinations.contains { $0.id == id }, "added browser survives settings reload")
            reloaded.forgetBrowserLocation(second.path)
            check(!reloaded.destinations.contains { $0.id == id }, "forgetting an unregistered added app removes its destination")
            try FileManager.default.removeItem(at: first)
            check(!BrowserCatalog.discover(customPaths: [first.path]).contains { $0.id == id }, "removed app locations are ignored")
            let actual = BrowserCatalog.discover()
            check(Set(actual.map(\.id)).count == actual.count, "registered browser and profile destinations have unique IDs")
            check(!actual.contains { $0.bundleID == Bundle.main.bundleIdentifier || $0.bundleID == "com.googlecode.iterm2" || $0.bundleID == "com.openai.codex" }, "picker and non-browser forwarding apps are excluded")
        } catch { check(false, "browser catalog fixture failure: " + error.localizedDescription) }
    }
}
