import AppKit
import PickerCore

@MainActor
private final class BrowserListView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class PickerPanel: NSPanel {
    var handleKey: ((NSEvent) -> Bool)?
    var handleModifiers: ((NSEvent.ModifierFlags) -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged { handleModifiers?(event.modifierFlags) }
        super.sendEvent(event)
    }
    override func keyDown(with event: NSEvent) {
        if handleKey?(event) != true { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleKey?(event) == true || super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class BrowserRow: NSButton {
    let destination: Destination
    var choose: ((Destination, NSEvent.ModifierFlags) -> Void)?
    private let background = NSView()
    private var tracking: NSTrackingArea?
    private let shortcut = NSTextField(labelWithString: "")
    private let number: Int
    var commandHeld = false { didSet { updateShortcut() } }
    var selected = false { didSet { updateAppearance() } }
    init(destination: Destination, icon: NSImage?, number: Int) {
        self.destination = destination
        self.number = number
        super.init(frame: NSRect(x: 0, y: 0, width: 380, height: 58))
        title = ""; isBordered = false; focusRingType = .none
        identifier = NSUserInterfaceItemIdentifier(destination.id)
        background.wantsLayer = true; background.layer?.cornerRadius = 10
        background.translatesAutoresizingMaskIntoConstraints = false; addSubview(background)
        let image = NSImageView(); image.image = icon; image.imageScaling = .scaleProportionallyUpOrDown
        image.translatesAutoresizingMaskIntoConstraints = false; image.setAccessibilityElement(false); addSubview(image)
        let name = NSTextField(labelWithString: destination.name)
        name.font = .systemFont(ofSize: 14, weight: .medium); name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false; name.setAccessibilityElement(false); addSubview(name)
        shortcut.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium); shortcut.textColor = .secondaryLabelColor
        shortcut.translatesAutoresizingMaskIntoConstraints = false; shortcut.setAccessibilityElement(false); addSubview(shortcut)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 58),
            background.leadingAnchor.constraint(equalTo: leadingAnchor), background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor), background.bottomAnchor.constraint(equalTo: bottomAnchor),
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 36), image.heightAnchor.constraint(equalToConstant: 36),
            name.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 12), name.centerYAnchor.constraint(equalTo: centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: shortcut.leadingAnchor, constant: -12),
            shortcut.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16), shortcut.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        target = self; action = #selector(clicked)
        updateShortcut()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { background.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor }
    override func mouseExited(with event: NSEvent) { updateAppearance() }
    func updateAppearance() { background.layer?.backgroundColor = (selected ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.clear).cgColor }
    private func updateShortcut() {
        shortcut.stringValue = number <= 9 ? (commandHeld ? "⌘" : "") + String(number) : ""
        setAccessibilityLabel(destination.name + (number <= 9 ? ", shortcut \(commandHeld ? "Command " : "")\(number)" : "") + (commandHeld ? ", remember for this website" : ""))
        toolTip = number <= 9 ? "Press \(number) to open once, or ⌘\(number) to open and remember this website." : "Command-click to open and remember this website."
    }
    @objc private func clicked() { choose?(destination, NSApp.currentEvent?.modifierFlags ?? []) }
}

@MainActor
final class PickerWindowController: NSWindowController, NSWindowDelegate {
    let store: AppStore
    private(set) var url: URL?
    private(set) var rows: [BrowserRow] = []
    private(set) var selected = 0
    private let remember = NSButton(checkboxWithTitle: "Always use this browser for this website", target: nil, action: nil)
    private let privateMode = NSButton(checkboxWithTitle: "Private window", target: nil, action: nil)
    private let heading = NSTextField(labelWithString: "Open link in…")
    private let domainLabel = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let rememberHint = NSTextField(labelWithString: "")
    private var manuallyRemember = false
    private var commandHeld = false
    private var canRememberWebsite: Bool { url?.isFileURL == false && !(url?.host ?? "").isEmpty }
    private var baseHeading = "Open link in…"
    private var cachedDestinations: [Destination]?
    private var cachedRowsHeight: CGFloat?
    private var returnApplication: NSRunningApplication?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var presentedAt: TimeInterval = 0
    var onChoose: ((Destination, Bool, Bool, Bool) -> Void)?
    var modifierFlagsProvider: () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }
    var onCancel: (() -> Void)?
    var onOutsideClick: (() -> Void)?
    var onSettings: (() -> Void)?
    init(store: AppStore) {
        self.store = store
        let panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 432, height: 420), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Open link"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.delegate = self
        panel.handleKey = { [weak self] in self?.key($0) ?? false }
        panel.handleModifiers = { [weak self] in self?.modifiersChanged($0) }
        remember.target = self; remember.action = #selector(rememberClicked)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func show(url: URL, queued: Int, failure: String? = nil) {
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            returnApplication = frontmost
        }
        self.url = url; selected = 0; manuallyRemember = false; commandHeld = false; remember.state = .off; privateMode.state = .off
        window?.title = url.isFileURL ? "Open file" : "Open link"
        baseHeading = failure == nil ? (url.isFileURL ? "Open file in…" : "Open link in…") : "Choose another browser"
        domainLabel.stringValue = url.isFileURL ? (url.lastPathComponent.isEmpty ? "Local file" : url.lastPathComponent) : (url.host ?? "Website")
        detail.stringValue = failure ?? (url.isFileURL ? url.path : url.absoluteString)
        detail.textColor = failure == nil ? .secondaryLabelColor : .systemRed
        detail.toolTip = url.absoluteString; detail.setAccessibilityLabel(url.absoluteString)
        updateQueued(queued)
        let destinations = store.shownDestinations
        let rowsHeight = maximumRowsHeight()
        if cachedDestinations != destinations || cachedRowsHeight != rowsHeight {
            cachedDestinations = destinations
            cachedRowsHeight = rowsHeight
            rebuildContent()
        }
        for (index, row) in rows.enumerated() { row.selected = index == 0 }
        modifiersChanged(modifierFlagsProvider())
        centerOnPointerScreen()
        presentedAt = ProcessInfo.processInfo.systemUptime
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(window)
        refreshOutsideClickMonitoring()
        // Activation completes asynchronously on a cold launch. Reassert the key window
        // after AppKit processes activation, without capturing an already-dismissed request.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.url != nil, window?.isVisible == true else { return }
            window?.makeKeyAndOrderFront(nil)
        }
    }
    private func rebuildContent() {
        let content = NSVisualEffectView(); content.material = .popover; content.blendingMode = .behindWindow; content.state = .active
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(heading)
        domainLabel.font = .systemFont(ofSize: 14, weight: .medium)
        domainLabel.lineBreakMode = .byTruncatingMiddle; domainLabel.maximumNumberOfLines = 1
        stack.addArrangedSubview(domainLabel)
        detail.font = .systemFont(ofSize: 11)
        detail.lineBreakMode = .byTruncatingMiddle; detail.maximumNumberOfLines = 1
        stack.addArrangedSubview(detail); stack.setCustomSpacing(16, after: detail)
        let rowStack = NSStackView(); rowStack.orientation = .vertical; rowStack.alignment = .leading; rowStack.spacing = 6
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rows = store.shownDestinations.enumerated().map { index, destination in
            let row = BrowserRow(destination: destination, icon: store.icons[destination.appPath], number: index + 1)
            row.choose = { [weak self] in self?.choose($0, flags: $1) }; rowStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true
            return row
        }
        if rows.isEmpty { rowStack.addArrangedSubview(NSTextField(labelWithString: "No browsers found. Add one in Settings.")) }
        let totalRowsHeight = max(58, CGFloat(rows.count) * 64 - 6)
        let visibleRowsHeight = min(totalRowsHeight, maximumRowsHeight())
        let document = BrowserListView(frame: NSRect(x: 0, y: 0, width: 384, height: totalRowsHeight))
        document.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: document.leadingAnchor), rowStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: document.topAnchor), rowStack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        scroll.documentView = document; scroll.translatesAutoresizingMaskIntoConstraints = false
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        document.heightAnchor.constraint(equalToConstant: totalRowsHeight).isActive = true
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: visibleRowsHeight).isActive = true
        stack.setCustomSpacing(14, after: scroll)
        remember.font = .systemFont(ofSize: 11); remember.setAccessibilityIdentifier("remember-domain")
        remember.toolTip = "Hold ⌘ to enable this while choosing. Release ⌘ to restore your manual choice."
        stack.addArrangedSubview(remember)
        rememberHint.font = .systemFont(ofSize: 10); rememberHint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(rememberHint)
        privateMode.font = .systemFont(ofSize: 11); privateMode.setAccessibilityIdentifier("private-window")
        privateMode.isHidden = !rows.contains { $0.destination.supportsPrivate }
        stack.addArrangedSubview(privateMode); stack.setCustomSpacing(12, after: privateMode)
        let footer = NSStackView(); footer.orientation = .horizontal; footer.spacing = 8
        let copy = NSButton(title: "Copy link", target: self, action: #selector(copyLink)); copy.bezelStyle = .inline
        let settings = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")!, target: self, action: #selector(settingsClicked)); settings.bezelStyle = .inline; settings.toolTip = "Settings"
        countLabel.font = .systemFont(ofSize: 10); countLabel.textColor = .tertiaryLabelColor
        footer.addArrangedSubview(copy); footer.addArrangedSubview(settings); footer.addArrangedSubview(NSView()); footer.addArrangedSubview(countLabel)
        stack.addArrangedSubview(footer); footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
        window?.contentView = content
        let height = 266 + visibleRowsHeight
        window?.setContentSize(NSSize(width: 432, height: height))
    }
    private func maximumRowsHeight() -> CGFloat {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        return max(58, (screen?.visibleFrame.height ?? 800) - 300)
    }
    func updateQueued(_ count: Int) { countLabel.stringValue = count > 0 ? "+\(count) queued" : "↑ ↓  ·  ↵  ·  esc" }
    func refreshDestinations() {
        guard url != nil, window?.isVisible == true, cachedDestinations != store.shownDestinations else { return }
        let selectedID = rows.indices.contains(selected) ? rows[selected].destination.id : nil
        cachedDestinations = store.shownDestinations; cachedRowsHeight = maximumRowsHeight()
        rebuildContent()
        selected = rows.firstIndex { $0.destination.id == selectedID } ?? 0
        for (index, row) in rows.enumerated() { row.selected = index == selected }
        updateRememberAppearance()
        if rows.indices.contains(selected) { rows[selected].scrollToVisible(rows[selected].bounds) }
        centerOnPointerScreen()
    }
    private func centerOnPointerScreen() {
        guard let window, let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: max(frame.minX, min(frame.midX - window.frame.width / 2, frame.maxX - window.frame.width)),
            y: max(frame.minY, min(frame.midY - window.frame.height / 2 + 60, frame.maxY - window.frame.height))
        ))
    }
    func dismiss(restoreFocus: Bool = false) {
        stopOutsideClickMonitoring()
        url = nil; window?.orderOut(nil)
        modifiersChanged([])
        if restoreFocus { returnApplication?.activate(options: []) }
        returnApplication = nil
    }
    func refreshOutsideClickMonitoring() {
        guard store.configuration.dismissPickerOnOutsideClick, url != nil, window?.isVisible == true else {
            stopOutsideClickMonitoring(); return
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if localClickMonitor == nil {
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                // AppKit invokes monitor handlers on its main thread.
                MainActor.assumeIsolated { self?.handleMouseDown(event) }
                return event
            }
        }
        if globalClickMonitor == nil {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                MainActor.assumeIsolated { self?.handleMouseDown(event) }
            }
        }
    }
    private func stopOutsideClickMonitoring() {
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor); self.localClickMonitor = nil }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor); self.globalClickMonitor = nil }
    }
    func handleMouseDown(_ event: NSEvent) {
        guard [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
              store.configuration.dismissPickerOnOutsideClick, url != nil,
              let window, window.isVisible, event.window !== window,
              event.timestamp >= presentedAt else { return }
        // An opening click can arrive late from the global monitor. The timestamp
        // check prevents it from cancelling the prompt it just opened.
        onOutsideClick?()
    }
    func key(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        modifiersChanged(modifiers)
        let char = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if modifiers.contains(.command) {
            if char == "c" { copyLink(); return true }
            if char == "," { settingsClicked(); return true }
            if let number = Int(char), (1...9).contains(number), rows.indices.contains(number - 1) {
                choose(rows[number - 1].destination, flags: modifiers); return true
            }
            return false
        }
        if event.keyCode == 53 { onCancel?(); return true }
        if event.keyCode == 125 || event.keyCode == 126 || event.keyCode == 48 {
            guard !rows.isEmpty else { return true }
            rows[selected].selected = false
            let backwards = event.keyCode == 126 || (event.keyCode == 48 && modifiers.contains(.shift))
            selected = (selected + (backwards ? rows.count - 1 : 1)) % rows.count
            rows[selected].selected = true; rows[selected].scrollToVisible(rows[selected].bounds); return true
        }
        if event.keyCode == 36 || event.keyCode == 76 || char == " " {
            if rows.indices.contains(selected) { choose(rows[selected].destination, flags: modifiers) }
            return true
        }
        if let number = Int(char), (1...9).contains(number), rows.indices.contains(number - 1) {
            choose(rows[number - 1].destination, flags: modifiers); return true
        }
        return false
    }
    private func choose(_ destination: Destination, flags: NSEvent.ModifierFlags) {
        modifiersChanged(flags)
        let wantsPrivate = privateMode.state == .on || flags.contains(.option)
        if wantsPrivate && !destination.supportsPrivate {
            detail.stringValue = "Private-window routing is unavailable for this browser."
            detail.textColor = .systemRed; NSSound.beep(); return
        }
        onChoose?(destination, canRememberWebsite && (manuallyRemember || flags.contains(.command)), wantsPrivate, flags.contains(.control))
    }
    private func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        commandHeld = flags.contains(.command)
        updateRememberAppearance()
    }
    private func updateRememberAppearance() {
        remember.isHidden = !canRememberWebsite; remember.isEnabled = canRememberWebsite
        let effectiveRemember = canRememberWebsite && (manuallyRemember || commandHeld)
        remember.state = effectiveRemember ? .on : .off
        heading.stringValue = effectiveRemember ? "Always open this site in…" : baseHeading
        for row in rows where row.commandHeld != commandHeld { row.commandHeld = commandHeld }
        let count = min(rows.count, 9)
        let shortcuts = count > 1 ? "⌘1–⌘\(count)" : count == 1 ? "⌘1" : "⌘-click"
        rememberHint.stringValue = canRememberWebsite
            ? (commandHeld ? "\(shortcuts) opens and remembers this website" : "Hold ⌘ to remember · \(shortcuts)")
            : "Choose a browser. Files open once."
    }
    @objc private func rememberClicked() {
        if !commandHeld { manuallyRemember = remember.state == .on }
        updateRememberAppearance()
    }
    func windowDidBecomeKey(_ notification: Notification) { modifiersChanged(modifierFlagsProvider()) }
    func windowDidResignKey(_ notification: Notification) { modifiersChanged([]) }
    @objc private func copyLink() {
        guard let url else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string)
        onCancel?()
    }
    @objc private func settingsClicked() { onSettings?() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { onCancel?(); return false }
}
