import AppKit
import PickerCore

@MainActor
private final class ClickEchoWindow: NSWindow {
    var receivedClicks = 0
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { receivedClicks += 1 }
        super.sendEvent(event)
    }
}

/// Exercises real AppKit windows and the complete incoming-link queue with an injected launcher.
@MainActor
enum SmokeTests {
    static var destinations: [Destination] {
        [Destination(id: "example.browser", name: "Example Browser", bundleID: "example.browser", appPath: "/Applications/Example Browser.app"),
         Destination(id: "com.google.Chrome", name: "Chrome", bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", supportsPrivate: true),
         Destination(id: "com.google.Chrome:Default", name: "Chrome · Work", bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", profile: "Default", supportsPrivate: true),
         Destination(id: "com.apple.Safari", name: "Safari", bundleID: "com.apple.Safari", appPath: "/Applications/Safari.app")]
    }
    static func run(_ app: AppDelegate) {
        var failures: [String] = []; var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            checks += 1; if !condition() { failures.append(name) }
        }
        BrowserCatalogChecks.run(check: { value, name in check(value, name) })
        func key(_ code: UInt16, _ text: String, flags: NSEvent.ModifierFlags = []) {
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: app.picker.window?.windowNumber ?? 0, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code) {
                app.picker.window?.sendEvent(event)
            }
        }
        func modifiers(_ flags: NSEvent.ModifierFlags) {
            if let event = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: app.picker.window?.windowNumber ?? 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 55) {
                app.picker.window?.sendEvent(event)
            }
        }
        func commandKey(_ code: UInt16, _ text: String) -> Bool {
            guard let panel = app.picker.window as? PickerPanel,
                  let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code) else { return false }
            return panel.performKeyEquivalent(with: event)
        }
        func findButton(_ view: NSView?, id: String) -> NSButton? {
            guard let view else { return nil }
            if let button = view as? NSButton, button.accessibilityIdentifier() == id { return button }
            return view.subviews.lazy.compactMap { findButton($0, id: id) }.first
        }
        let url = URL(string: "https://example.com/a?x=1#fragment")!
        // Keep unrelated real desktop clicks from interrupting keyboard regressions.
        // Outside-click behavior is exercised separately below with the option enabled.
        app.store.update { $0.dismissPickerOnOutsideClick = false }
        app.journal(["event": "native-keyboard-environment", "modifiers": NSEvent.modifierFlags.rawValue])
        app.picker.modifierFlagsProvider = { [] }
        app.launcher.simulated = true
        var opened: [String] = []
        var openedIDs: [String] = []
        var privateFlags: [Bool] = []; var backgroundFlags: [Bool] = []
        app.launcher.onSimulatedOpen = { url, destination, privateMode, background in opened.append(url.absoluteString); openedIDs.append(destination.id); privateFlags.append(privateMode); backgroundFlags.append(background) }
        app.enqueue(LinkRequest(url: url, forcePrompt: true))
        check(app.picker.window?.isVisible == true, "picker visible")
        check(app.picker.window?.canBecomeKey == true, "picker accepts keyboard focus")
        check(app.picker.rows.count == app.store.shownDestinations.count, "all browsers rendered")
        check(!app.picker.rows.isEmpty, "installed browsers discovered")
        let hiddenID = app.store.shownDestinations[0].id
        app.store.update { $0.hiddenDestinationIDs.insert(hiddenID) }
        check(!app.picker.rows.contains { $0.destination.id == hiddenID }, "browser visibility changes refresh an open picker")
        app.store.update { $0.hiddenDestinationIDs.removeAll() }
        check(app.picker.rows.count == destinations.count, "unhidden browsers return to an open picker")
        check(app.picker.rows[app.picker.selected].destination.id == "com.google.Chrome", "refresh preserves the selected browser identity")
        app.picker.show(url: url, queued: 0)
        app.picker.window?.contentView?.layoutSubtreeIfNeeded()
        check(app.picker.rows.allSatisfy { $0.frame.width <= ($0.enclosingScrollView?.contentView.bounds.width ?? 0) }, "row shortcuts fit inside the scroll viewport")
        key(125, ""); check(app.picker.selected == 1 % max(1, app.picker.rows.count), "down arrow")
        key(126, ""); check(app.picker.selected == 0, "up arrow")
        key(48, "\t", flags: .shift); check(app.picker.selected == app.picker.rows.count - 1, "shift tab wraps")
        key(48, "\t"); check(app.picker.selected == 0, "tab wraps")
        let pasteboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
        key(8, "c", flags: .command)
        check(NSPasteboard.general.string(forType: .string) == url.absoluteString, "copy exact URL")
        check(app.activeRequest == nil, "copy completes request")
        check(app.store.configuration.rules.isEmpty, "Command-C does not remember a website")
        func restorePasteboard() {
            NSPasteboard.general.clearContents()
            // Pasteboard items cannot be reused after their first write.
            let items = pasteboard.map { representations in
                let item = NSPasteboardItem(); for (type, data) in representations { item.setData(data, forType: type) }; return item
            }
            NSPasteboard.general.writeObjects(items)
        }
        restorePasteboard()
        app.enqueue(LinkRequest(url: url, forcePrompt: true)); key(53, "")
        check(app.activeRequest == nil && app.picker.window?.isVisible == false, "escape dismisses")
        app.enqueue(LinkRequest(url: url, forcePrompt: true)); key(18, "1")
        check(opened == [url.absoluteString], "number opens selected browser")
        app.enqueue(LinkRequest(url: url, forcePrompt: true)); key(36, "\r")
        check(opened.count == 2, "return opens selected browser")
        app.enqueue(LinkRequest(url: url, forcePrompt: true))
        let beforePrivate = opened.count
        key(18, "1", flags: .option)
        check(app.activeRequest != nil && opened.count == beforePrivate, "unsupported private browser stays in picker")
        key(19, "2", flags: [.option, .control])
        check(privateFlags.last == true && backgroundFlags.last == true, "private and background flags reach launcher")
        app.enqueue(LinkRequest(url: url, forcePrompt: true))
        let checkbox = findButton(app.picker.window?.contentView, id: "remember-domain")
        check(checkbox != nil, "remember checkbox accessible")
        app.picker.window?.makeFirstResponder(checkbox)
        modifiers(.command)
        check(checkbox?.state == .on, "holding Command visibly checks remember even when checkbox has focus")
        check(app.picker.rows.first?.accessibilityLabel()?.contains("shortcut Command 1") == true, "holding Command shows and announces Command-number shortcuts")
        modifiers([])
        check(checkbox?.state == .off, "releasing Command restores unchecked choice")
        check(app.picker.rows.first?.accessibilityLabel()?.contains("shortcut Command 1") == false, "releasing Command restores plain number shortcuts")
        checkbox?.performClick(nil)
        modifiers(.command); modifiers([])
        check(checkbox?.state == .on, "releasing Command preserves a manually checked choice")
        checkbox?.performClick(nil)
        check(checkbox?.state == .off, "manual checkbox can be cleared after releasing Command")
        key(53, "")
        let numberCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        for index in 0..<min(app.store.shownDestinations.count, 9) {
            app.enqueue(LinkRequest(url: url, forcePrompt: true))
            check(checkbox?.state == .off, "remember resets on a new link")
            let id = app.store.shownDestinations[index].id
            check(commandKey(numberCodes[index], String(index + 1)), "Command-number handled as a native key equivalent")
            check(app.activeRequest == nil && openedIDs.last == id, "Command-number opens the correct browser")
            check(app.store.configuration.rules.first?.domain == "example.com" && app.store.configuration.rules.first?.destinationID == id, "Command-number persists the correct website rule")
        }
        app.store.update { $0.rules.removeAll() }
        app.enqueue(LinkRequest(url: url, forcePrompt: true))
        let openedBeforeInvalid = opened.count
        _ = commandKey(25, "9")
        check(app.activeRequest != nil && opened.count == openedBeforeInvalid && app.store.configuration.rules.isEmpty, "out-of-range Command-number does not launch or remember")
        modifiers([]); key(53, "")
        app.enqueue(LinkRequest(url: url, forcePrompt: true))
        key(19, "2", flags: [.command, .control])
        check(backgroundFlags.last == true && app.store.configuration.rules.first?.destinationID == app.store.shownDestinations[1].id, "Command-Control-number opens in background and remembers")
        app.store.update { $0.rules.removeAll() }
        app.enqueue(LinkRequest(url: url, forcePrompt: true))
        key(19, "2", flags: [.command, .option])
        check(privateFlags.last == true && app.store.configuration.rules.first?.privateWindow == true, "Command-Option-number remembers private browsing")
        app.store.update { $0.rules.removeAll() }
        app.enqueue(LinkRequest(url: url, forcePrompt: true))
        checkbox?.performClick(nil); key(18, "1")
        check(app.store.configuration.rules.first?.domain == "example.com", "remember creates website rule")
        check(app.store.configuration.rules.first?.destinationID == app.store.shownDestinations.first?.id, "remember uses chosen target")
        app.store.update { $0.rules.removeAll() }
        app.enqueue(LinkRequest(url: url, forcePrompt: true))
        checkbox?.performClick(nil)
        app.launcher.simulated = false
        let missing = Destination(id: "missing", name: "Missing browser", bundleID: "local.missing", appPath: "/tmp/browser-picker-missing-browser.app")
        app.picker.onChoose?(missing, true, false, false)
        check(app.activeRequest != nil && app.picker.window?.isVisible == true, "failed launch retains link and reopens picker")
        check(app.store.configuration.rules.isEmpty, "failed launch does not save remembered choice")
        app.launcher.simulated = true; key(18, "1")
        check(app.activeRequest == nil, "failed link can be retried in another browser")
        // Exercise the same URL event used by Finder and Launch Services.
        var openErrors: [String] = []
        app.onOpenError = { openErrors.append($0) }
        let fileURLs = [URL(fileURLWithPath: "/tmp/Browser Picker 日本語 #100%+?.html"),
                        URL(fileURLWithPath: "/tmp/browser-picker-missing.unknown"),
                        URL(string: "file://localhost/tmp/report.html?utm_source=keep#section")!]
        for file in fileURLs {
            app.application(NSApp, open: [file])
            check(app.activeRequest?.url == file && app.picker.window?.isVisible == true, "file URL reaches picker unchanged")
            check(app.picker.window?.title == "Open file", "file picker identifies a file")
            let fileRemember = findButton(app.picker.window?.contentView, id: "remember-domain")
            modifiers(.command)
            check(fileRemember?.isHidden == true && fileRemember?.state == .off, "file picker does not offer website remembering on Command")
            check(commandKey(18, "1"), "Command-number can open a file")
            check(opened.last == file.absoluteString && app.activeRequest == nil, "file address reaches browser unchanged")
            check(app.store.configuration.rules.isEmpty, "opening a file never creates a website rule")
        }
        check(openErrors.isEmpty && app.store.errorMessage == nil && app.settings.window?.isVisible == false, "file opens produce no validation warning or settings window")
        app.application(NSApp, open: fileURLs)
        for file in fileURLs {
            check(app.activeRequest?.url == file, "multiple Finder files retain their order")
            key(18, "1"); app.resumeQueuedLinks()
        }
        check(app.activeRequest == nil, "multiple file queue drains fully")
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(fileURLs as [NSURL])
        app.openClipboard()
        for file in fileURLs {
            check(app.activeRequest?.url == file, "Finder clipboard files use file URLs")
            key(18, "1"); app.resumeQueuedLinks()
        }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(fileURLs[0].path, forType: .string)
        app.openClipboard(); key(19, "2", flags: .option)
        check(opened.last == fileURLs[0].absoluteString && privateFlags.last == true, "clipboard file path works with private browser routing")
        restorePasteboard()
        app.enqueue(LinkRequest(url: fileURLs[0], forcePrompt: true))
        app.launcher.simulated = false
        app.picker.onChoose?(missing, true, false, false)
        check(app.activeRequest?.url == fileURLs[0] && app.picker.window?.isVisible == true, "failed browser launch retains file for retry")
        app.launcher.simulated = true; key(18, "1")
        check(app.store.configuration.rules.isEmpty, "file retry cannot remember a website")
        app.enqueue(LinkRequest(url: URL(string: "mailto:example@example.com")!))
        check(openErrors.count == 1 && app.store.errorMessage == nil && app.settings.window?.isVisible == false, "invalid link errors stay out of Settings")
        app.enqueue(LinkRequest(url: url, forcePrompt: true))
        check(findButton(app.picker.window?.contentView, id: "remember-domain")?.isHidden == false, "website remembering returns after opening files")
        key(53, "")
        app.store.update { $0.hiddenDestinationIDs = Set(app.store.destinations.map(\.id)) }
        app.enqueue(LinkRequest(url: url, forcePrompt: true))
        check(app.picker.rows.count == app.store.destinations.count, "all-hidden configuration still offers browsers")
        key(53, ""); app.store.update { $0.hiddenDestinationIDs.removeAll() }
        // Real SwiftUI settings view, sized and laid out in its native hosting window.
        app.enqueue(LinkRequest(url: url, forcePrompt: true))
        check(commandKey(43, ","), "Command-comma still opens settings")
        check(app.activeRequest != nil && app.store.configuration.rules.isEmpty, "Command-comma does not open or remember the pending link")
        app.settings.window?.contentView?.layoutSubtreeIfNeeded()
        check(app.settings.window?.isVisible == true, "settings visible")
        app.settings.window?.orderOut(nil)
        key(53, "")
        func beginQueueTests() {
            let many = (0..<40).map { Destination(id: "example.\($0)", name: "Browser \($0)", bundleID: "example.\($0)", appPath: "/Applications/Example.app") }
            let manyStore = AppStore(settingsURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"), destinations: many)
            let manyPicker = PickerWindowController(store: manyStore)
            manyPicker.show(url: url, queued: 0)
            manyPicker.window?.contentView?.layoutSubtreeIfNeeded()
            check(manyPicker.rows.count == 40, "large browser list retains every destination")
            check(manyPicker.window!.frame.height <= (NSScreen.main?.visibleFrame.height ?? 800), "large browser picker fits on screen")
            check(NSScreen.screens.contains { $0.visibleFrame.contains(manyPicker.window!.frame) }, "large browser picker stays within screen edges")
            for _ in 0..<39 {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: manyPicker.window!.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125)!
                _ = manyPicker.key(event)
            }
            check(manyPicker.selected == 39, "arrow navigation reaches destinations beyond number shortcuts")
            check(!manyPicker.rows[39].visibleRect.isEmpty, "keyboard selection scrolls the last browser into view")
            manyPicker.dismiss()
            app.store.update { $0.dismissPickerOnOutsideClick = false }
            for index in 0..<25 {
                app.enqueue(LinkRequest(url: URL(string: "https://example.com/queue/\(index)")!, forcePrompt: true))
            }
            DispatchQueue.main.async { drain(25) }
        }
        func drain(_ remaining: Int) {
            if remaining > 0 {
                check(app.activeRequest != nil, "queued request \(25 - remaining) retained")
                key(18, "1")
                DispatchQueue.main.async { drain(remaining - 1) }
            } else {
                check(app.activeRequest == nil, "queue fully drained")
                let tail = Array(opened.suffix(25))
                check(tail == (0..<25).map { "https://example.com/queue/\($0)" }, "queue preserves order and every URL")
                // Window activation is asynchronous; verify focus after its run-loop delivery,
                // then send through NSApplication, just as a real keyboard event arrives.
                app.enqueue(LinkRequest(url: url, forcePrompt: true))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    check(app.picker.window?.isKeyWindow == true, "picker receives keyboard focus after activation")
                    if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: app.picker.window?.windowNumber ?? 0, context: nil, characters: "4", charactersIgnoringModifiers: "4", isARepeat: false, keyCode: 21) { NSApp.sendEvent(event) }
                    check(app.activeRequest == nil, "system-dispatched keyboard event opens browser")
                    check(app.store.configuration.rules.first?.destinationID == app.store.shownDestinations[3].id, "system-dispatched Command-4 remembers the selected browser")
                    // Read-only regression for the reported setup warning: only exercise
                    // Make Default if the system already points both schemes at this app.
                    if app.store.isDefault {
                        app.store.makeDefault()
                        check(app.store.isDefault, "already active browser remains active")
                        check(!app.store.makingDefault, "already active browser makes no system request")
                        check(app.store.defaultBrowserSetupMessage == nil, "already active browser has no setup warning")
                        check(app.store.errorMessage == nil, "default setup does not create a global warning")
                    }
                    app.journal(["event": "smoke-result", "checks": checks, "failures": failures])
                    print("Native smoke tests: \(checks) checks, \(failures.count) failures \(failures)")
                    fflush(stdout)
                    exit(failures.isEmpty ? 0 : 1)
                }
            }
        }
        // Real local monitor and native event delivery: clicking another window
        // closes only the picker and still delivers the click to its target view.
        let otherWindow = ClickEchoWindow(contentRect: NSRect(x: 20, y: 20, width: 120, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        otherWindow.title = "Outside-click test"; otherWindow.isReleasedWhenClosed = false
        otherWindow.orderFront(nil)
        func mouse(_ type: NSEvent.EventType = .leftMouseDown, in window: NSWindow?, timestamp: TimeInterval? = nil) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: timestamp ?? ProcessInfo.processInfo.systemUptime, windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        app.store.update { $0.dismissPickerOnOutsideClick = true }
        app.enqueue(LinkRequest(url: url, forcePrompt: true))
        let openedBeforeOutside = opened.count
        app.picker.handleMouseDown(mouse(in: app.picker.window))
        check(app.activeRequest != nil, "inside click does not dismiss picker")
        app.picker.handleMouseDown(mouse(in: otherWindow, timestamp: 0))
        check(app.activeRequest != nil, "late opening click does not dismiss fresh picker")
        app.store.update { $0.dismissPickerOnOutsideClick = false }
        app.picker.handleMouseDown(mouse(in: otherWindow))
        check(app.activeRequest != nil, "disabled outside-click option keeps picker open")
        app.store.update { $0.dismissPickerOnOutsideClick = true }
        NSApp.postEvent(mouse(in: otherWindow), atStart: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            check(app.activeRequest == nil && app.picker.window?.isVisible == false, "real local outside-click monitor closes picker")
            check(otherWindow.receivedClicks == 1, "outside click is forwarded to its original window")
            check(opened.count == openedBeforeOutside && app.store.configuration.rules.isEmpty, "outside click neither opens nor remembers a browser")
            // Duplicate/stale callbacks cannot cancel a different request.
            app.picker.handleMouseDown(mouse(in: otherWindow))
            check(app.activeRequest == nil, "outside event after dismissal is harmless")
            let first = URL(string: "https://example.com/outside/first")!
            let second = URL(string: "https://example.com/outside/second")!
            let third = URL(string: "https://example.com/outside/third")!
            app.enqueue(LinkRequest(url: first, forcePrompt: true))
            app.enqueue(LinkRequest(url: second, forcePrompt: true))
            app.enqueue(LinkRequest(url: third, forcePrompt: true))
            app.picker.handleMouseDown(mouse(.rightMouseDown, in: otherWindow))
            check(app.activeRequest == nil && app.picker.window?.isVisible == false, "right outside click dismisses and pauses queued prompts")
            DispatchQueue.main.async {
                check(app.activeRequest == nil && app.picker.window?.isVisible == false, "scheduled queue work cannot reopen an outside-dismissed picker")
                app.resumeQueuedLinks()
                check(app.activeRequest?.url == second, "resume retains the next queued URL")
                key(53, "")
                check(app.activeRequest?.url == third, "remaining queued URLs keep their order")
                key(53, "")
                app.enqueue(LinkRequest(url: first, forcePrompt: true))
                app.picker.handleMouseDown(mouse(.otherMouseDown, in: otherWindow))
                check(app.activeRequest == nil, "middle outside click also dismisses")
                app.enqueue(LinkRequest(url: second, forcePrompt: true))
                check(app.activeRequest?.url == second && app.picker.window?.isVisible == true, "a new link opens a picker after outside dismissal")
                key(18, "1")
                check(app.activeRequest == nil && app.picker.window?.isVisible == false, "browser selection still succeeds with outside dismissal enabled")
                otherWindow.close()
                beginQueueTests()
            }
        }
    }
}
