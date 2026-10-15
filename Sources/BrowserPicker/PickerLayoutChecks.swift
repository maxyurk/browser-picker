import AppKit
import PickerCore

@MainActor
enum PickerLayoutChecks {
    static func run(check: (Bool, String) -> Void) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("picker-layout-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(settingsURL: directory.appendingPathComponent("settings.json"), destinations: SmokeTests.destinations)
        let picker = PickerWindowController(store: store)
        picker.modifierFlagsProvider = { [] }
        defer { picker.dismiss() }

        func verify(_ controller: PickerWindowController, _ name: String) {
            guard let window = controller.window, let content = window.contentView else {
                check(false, "\(name): picker window exists"); return
            }
            content.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            check(abs(window.frame.width - 432) < 0.5, "\(name): window keeps its compact width")
            check(content.fittingSize.width <= 432.5, "\(name): text cannot increase the minimum window width")
            check(controller.rows.allSatisfy { $0.frame.width <= 384.5 && $0.frame.width > 300 }, "\(name): browser rows stay within the popup")
            check(NSScreen.screens.contains { $0.visibleFrame.contains(window.frame) }, "\(name): popup stays inside a screen")
        }

        let shortURL = URL(string: "https://example.com/")!
        picker.show(url: shortURL, queued: 0)
        verify(picker, "Short URL")

        let host = Array(repeating: String(repeating: "a", count: 45), count: 4).joined(separator: ".") + ".example"
        let longURL = URL(string: "https://\(host)/" + String(repeating: "path/", count: 100) + "?token=" + String(repeating: "a", count: 2048))!
        picker.show(url: longURL, queued: 12)
        verify(picker, "Long URL on a reused popup")
        let labels = picker.window?.contentView?.subviews.flatMap { $0.subviews }.compactMap { $0 as? NSTextField } ?? []
        check(labels.contains { $0.accessibilityLabel() == longURL.absoluteString && $0.toolTip == longURL.absoluteString }, "truncated URL retains its complete accessible label and tooltip")

        picker.modifierFlagsProvider = { [.command] }
        picker.show(url: longURL, queued: 0)
        verify(picker, "Command remember mode")
        picker.modifierFlagsProvider = { [] }

        let file = URL(fileURLWithPath: "/tmp/" + String(repeating: "Long filename 日本語 ", count: 60) + ".html")
        picker.show(url: file, queued: 0)
        verify(picker, "Long local filename")
        picker.show(url: shortURL, queued: 0, failure: String(repeating: "The browser could not open this link. ", count: 50))
        verify(picker, "Long browser error")
        picker.show(url: shortURL, queued: 0)
        verify(picker, "Short URL after long text")
        picker.dismiss()

        let longName = String(repeating: "Long browser profile · ", count: 40)
        let longNames = AppStore(settingsURL: directory.appendingPathComponent("long-names.json"), destinations: [
            Destination(id: "example.long", name: longName, bundleID: "example.long", appPath: "/Applications/Example.app", supportsPrivate: true)
        ])
        let longNamePicker = PickerWindowController(store: longNames)
        longNamePicker.modifierFlagsProvider = { [] }
        longNamePicker.show(url: longURL, queued: 0)
        verify(longNamePicker, "Long names on a fresh popup")
        longNamePicker.dismiss()
    }
}
