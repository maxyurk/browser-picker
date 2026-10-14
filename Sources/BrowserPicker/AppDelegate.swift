import AppKit
import PickerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: AppStore
    let launcher = BrowserLauncher()
    lazy var picker = PickerWindowController(store: store)
    lazy var settings = SettingsWindowController(store: store) { [weak self] in self?.enqueue(LinkRequest(url: $0, forcePrompt: true)) }
    private var statusItem: NSStatusItem?
    private var queue = RequestQueue()
    private(set) var activeRequest: LinkRequest?
    private var launching = false
    private var ready = false
    private var receivedURL = false
    private var queuePaused = false
    var onOpenError: (String) -> Void = { message in
        let alert = NSAlert()
        alert.messageText = "Could not open link or file"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    let started = CFAbsoluteTimeGetCurrent()

    override init() {
        let args = CommandLine.arguments
        let settingsPath = args.firstIndex(of: "--test-settings").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        if args.contains("--smoke-test") && settingsPath == nil {
            fputs("Native smoke tests require --test-settings with an isolated settings path.\n", stderr); exit(1)
        }
        store = AppStore(settingsURL: settingsPath.map { URL(fileURLWithPath: $0) }, destinations: args.contains("--smoke-test") ? SmokeTests.destinations : nil)
        super.init()
        if args.contains("--simulate") {
            launcher.simulated = true
            launcher.onSimulatedOpen = { [weak self] url, destination, privateMode, background in
                self?.journal(["event": "opened", "url": url.absoluteString, "destination": destination.id, "private": privateMode, "background": background])
            }
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        ready = true
        setupMenu()
        store.onChange = { [weak self] in
            self?.rebuildMenu(); self?.picker.refreshDestinations(); self?.picker.refreshOutsideClickMonitoring()
        }
        picker.onChoose = { [weak self] destination, remember, privateMode, background in
            guard let self, let request = activeRequest, !launching else { return }
            // Remember the final (unwrapped) destination, not a redirect service.
            let host = remember && picker.url?.isFileURL == false ? picker.url?.host : nil
            open(picker.url ?? request.url, destination: destination, privateWindow: privateMode, background: background, rememberHost: host)
        }
        picker.onCancel = { [weak self] in
            guard let self, !launching else { return }
            journal(["event": "cancelled", "url": activeRequest?.url.absoluteString ?? ""])
            picker.dismiss(restoreFocus: true); activeRequest = nil; pump()
        }
        picker.onOutsideClick = { [weak self] in
            guard let self, !launching, activeRequest != nil else { return }
            journal(["event": "cancelled", "reason": "outside-click", "url": activeRequest?.url.absoluteString ?? ""])
            queuePaused = true
            picker.dismiss(); activeRequest = nil; rebuildMenu()
        }
        picker.onSettings = { [weak self] in self?.settings.present() }
        journal(["event": "ready", "startup_ms": (CFAbsoluteTimeGetCurrent() - started) * 1000, "destinations": store.destinations.map(\.id)])
        pump()
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { SmokeTests.run(self) }
        } else if CommandLine.arguments.contains("--integration-test") {
            BrowserIntegrationTests.run(self)
        } else if let index = CommandLine.arguments.firstIndex(of: "--pick"), CommandLine.arguments.indices.contains(index + 1) {
            do { enqueue(LinkRequest(url: try OpenTarget.parse(CommandLine.arguments[index + 1], allowBareHost: true), forcePrompt: true)) }
            catch { reportOpenError(error) }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, !receivedURL, !store.loginEnabled else { return }
                settings.present()
            }
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        receivedURL = true
        let event = NSAppleEventManager.shared().currentAppleEvent
        let pid = event?.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let source = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        let flags = NSEvent.modifierFlags
        for url in urls { enqueue(LinkRequest(url: url, sourceBundleID: source, forcePrompt: flags.contains(.function) || flags.contains(.option))) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if activeRequest != nil { picker.window?.makeKeyAndOrderFront(nil) }
        else if queue.count > 0 { resumeQueuedLinks() }
        else { settings.present() }; return true
    }
    func applicationDidBecomeActive(_ notification: Notification) { store.refreshStatus() }
    func enqueue(_ request: LinkRequest) {
        receivedURL = true
        do { _ = try OpenTarget.process(request.url, unwrap: false, cleanTracking: false) }
        catch { reportOpenError(error); return }
        let wasPaused = queuePaused
        queue.append(request); queuePaused = false; picker.updateQueued(queue.count)
        if wasPaused { rebuildMenu() }
        journal(["event": "received", "url": request.url.absoluteString, "source": request.sourceBundleID ?? "unknown"])
        if ready { pump() }
    }
    private func pump() {
        guard ready, !queuePaused, activeRequest == nil, !launching, let request = queue.pop() else { return }
        activeRequest = request
        let start = CFAbsoluteTimeGetCurrent()
        do {
            switch try Router.route(request, configuration: store.configuration, destinations: store.destinations) {
            case .prompt(let url):
                picker.show(url: url, queued: queue.count)
                journal(["event": "prompt", "url": url.absoluteString, "queue": queue.count, "render_ms": (CFAbsoluteTimeGetCurrent() - start) * 1000])
            case .open(let url, let destination, let privateMode): open(url, destination: destination, privateWindow: privateMode, background: false)
            }
        } catch {
            reportOpenError(error); activeRequest = nil
            DispatchQueue.main.async { [weak self] in self?.pump() }
        }
    }
    private func open(_ url: URL, destination: Destination, privateWindow: Bool, background: Bool, rememberHost: String? = nil) {
        launching = true; picker.window?.orderOut(nil)
        picker.refreshOutsideClickMonitoring()
        launcher.open(url, in: destination, privateWindow: privateWindow, background: background) { [weak self] error in
            guard let self else { return }
            launching = false
            if let error {
                store.refresh()
                picker.show(url: url, queued: queue.count, failure: error.localizedDescription)
            } else {
                if let rememberHost { store.remember(rememberHost, destination: destination, privateWindow: privateWindow) }
                picker.dismiss(restoreFocus: background); activeRequest = nil
                // Yield between auto-routed links, avoiding recursion and keeping input responsive.
                DispatchQueue.main.async { [weak self] in self?.pump() }
            }
        }
    }
    private func setupMenu() {
        let main = NSMenu()
        let app = NSMenuItem(); let submenu = NSMenu()
        submenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Quit Browser Picker", action: #selector(quit), keyEquivalent: "q").target = self
        app.submenu = submenu; main.addItem(app); NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Browser Picker")
        statusItem?.button?.toolTip = "Browser Picker"
        rebuildMenu()
    }
    private func rebuildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Browser Picker", action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
        menu.addItem(withTitle: "Open link from clipboard…", action: #selector(openClipboard), keyEquivalent: "").target = self
        if queuePaused && queue.count > 0 {
            menu.addItem(withTitle: "Resume \(queue.count) queued link\(queue.count == 1 ? "" : "s")…", action: #selector(resumeQueuedLinks), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        let ask = menu.addItem(withTitle: "Always ask", action: #selector(setDefault(_:)), keyEquivalent: "")
        ask.target = self; ask.representedObject = "prompt"; ask.state = store.configuration.defaultDestinationID == "prompt" ? .on : .off
        for destination in store.destinations {
            let item = menu.addItem(withTitle: destination.name, action: #selector(setDefault(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = destination.id
            item.state = store.configuration.defaultDestinationID == destination.id ? .on : .off
            if let icon = store.icons[destination.appPath]?.copy() as? NSImage { icon.size = NSSize(width: 18, height: 18); item.image = icon }
        }
        menu.addItem(.separator())
        if !store.isDefault { menu.addItem(withTitle: "Make default browser…", action: #selector(makeDefault), keyEquivalent: "").target = self }
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem?.menu = menu
    }
    @objc private func setDefault(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.update { $0.defaultDestinationID = id }
    }
    @objc func openClipboard() {
        do {
            if let files = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
                for file in files { enqueue(LinkRequest(url: file, forcePrompt: true)) }
                return
            }
            guard let text = NSPasteboard.general.string(forType: .string) else { throw PickerError.invalidURL }
            enqueue(LinkRequest(url: try OpenTarget.parse(text, allowBareHost: true), forcePrompt: true))
        } catch { reportOpenError(error) }
    }
    private func reportOpenError(_ error: Error) {
        receivedURL = true
        if ready { onOpenError(error.localizedDescription) }
        else { DispatchQueue.main.async { [weak self] in self?.onOpenError(error.localizedDescription) } }
    }
    @objc private func makeDefault() { store.makeDefault(); settings.present() }
    @objc func resumeQueuedLinks() { queuePaused = false; rebuildMenu(); pump() }
    @objc private func showSettings() { store.refreshStatus(); settings.present() }
    @objc private func quit() { NSApp.terminate(nil) }
    func journal(_ fields: [String: Any]) {
        guard let index = CommandLine.arguments.firstIndex(of: "--journal"), CommandLine.arguments.indices.contains(index + 1),
              let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
        let path = CommandLine.arguments[index + 1]
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        do { try handle.seekToEnd(); try handle.write(contentsOf: data + Data([10])) } catch { }
    }
}
