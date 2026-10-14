import AppKit
import SwiftUI
import PickerCore

// Render the real app views with illustrative data. This helper is compiled
// separately; it never runs in the shipped app or opens a user's settings.
@main
struct ScreenshotExporter {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("Usage: ScreenshotExporter OUTPUT_DIRECTORY\n", stderr)
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .aqua)
        let session = ScreenshotSession(output: URL(fileURLWithPath: CommandLine.arguments[1]))
        app.delegate = session
        withExtendedLifetime(session) { app.run() }
    }
}

@MainActor
private final class ScreenshotSession: NSObject, NSApplicationDelegate {
    let output: URL
    private var picker: PickerWindowController?
    private var settings: NSWindow?
    private var previousApp: NSRunningApplication?
    init(output: URL) { self.output = output }

    func applicationDidFinishLaunching(_ notification: Notification) {
        previousApp = NSWorkspace.shared.frontmostApplication
        Task {
            do {
                try await export()
                previousApp?.activate(options: [])
                NSApp.terminate(nil)
            } catch {
                fputs("Screenshot export failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    private func export() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("BrowserPicker-Screenshots-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        func appPath(_ id: String, fallback: String) -> String {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path ?? fallback
        }
        let chrome = appPath("com.google.Chrome", fallback: "/Applications/Google Chrome.app")
        let destinations = [
            Destination(id: "orion", name: "Orion", bundleID: "com.kagi.kagimacOS", appPath: appPath("com.kagi.kagimacOS", fallback: "/Applications/Orion.app")),
            Destination(id: "chrome", name: "Chrome", bundleID: "com.google.Chrome", appPath: chrome, supportsPrivate: true),
            Destination(id: "chrome-work", name: "Chrome · Work", bundleID: "com.google.Chrome", appPath: chrome, profile: "Default", supportsPrivate: true),
            Destination(id: "safari", name: "Safari", bundleID: "com.apple.Safari", appPath: appPath("com.apple.Safari", fallback: "/Applications/Safari.app"))
        ]
        let store = AppStore(settingsURL: temporary.appendingPathComponent("settings.json"), destinations: destinations)
        store.isDefault = true
        guard store.update({ configuration in
            configuration.dismissPickerOnOutsideClick = false
            configuration.rules = [
                Rule(domain: "github.com", destinationID: "chrome-work"),
                Rule(domain: "developer.apple.com", destinationID: "orion"),
                Rule(domain: "wikipedia.org", destinationID: "safari")
            ]
        }) else { throw ExportError.save }

        let picker = PickerWindowController(store: store)
        picker.modifierFlagsProvider = { [] }
        self.picker = picker
        picker.show(url: URL(string: "https://github.com/example/project")!, queued: 0)
        try await settle()
        try capture(picker.window!, name: "picker.png")
        (picker.window as? PickerPanel)?.handleModifiers?([.command])
        try await settle()
        try capture(picker.window!, name: "picker-remember.png")
        picker.dismiss()
        store.update { $0.dismissPickerOnOutsideClick = true }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 540), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Browser Picker"
        window.isReleasedWhenClosed = false
        window.center()
        settings = window
        for (tab, name) in [(SettingsTab.general, "settings.png"), (.browsers, "browsers.png"), (.rules, "rules.png")] {
            window.contentView = NSHostingView(rootView: SettingsView(store: store, onTest: { _ in }, selectedTab: tab))
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window)
            try await settle()
            window.makeKeyAndOrderFront(nil)
            try capture(window, name: name)
        }
        window.orderOut(nil)
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(350))
    }

    private func capture(_ window: NSWindow, name: String) throws {
        guard let view = window.contentView?.superview else { throw ExportError.render }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw ExportError.render }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ExportError.render }
        try png.write(to: output.appendingPathComponent(name), options: .atomic)
        print("Exported \(name) (\(bitmap.pixelsWide) × \(bitmap.pixelsHigh))")
    }

    private enum ExportError: Error { case save, render }
}
