import AppKit
import SwiftUI
import PickerCore
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController {
    init(store: AppStore, onTest: @escaping (URL) -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 540), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Browser Picker"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(store: store, onTest: onTest))
        super.init(window: window); window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); }
}

enum SettingsTab: Hashable { case general, browsers, rules }

struct SettingsView: View {
    @ObservedObject var store: AppStore
    let onTest: (URL) -> Void
    @State var selectedTab: SettingsTab = .general
    @State private var testURL = "https://example.com"
    @State private var editingRule: Rule?
    @State private var localError: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 25, weight: .medium)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Browser Picker").font(.title2.weight(.semibold))
                    Text("Your links. Your browsers.").foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.isDefault ? "Active" : "Setup needed").font(.caption.weight(.medium)).foregroundStyle(store.isDefault ? .green : .secondary)
            }.padding(24)
            TabView(selection: $selectedTab) {
                general.tabItem { Text("General") }.tag(SettingsTab.general)
                browsers.tabItem { Text("Browsers") }.tag(SettingsTab.browsers)
                rules.tabItem { Text("Rules") }.tag(SettingsTab.rules)
            }.padding(.horizontal, 16).padding(.bottom, 16)
            if let message = store.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(message).font(.caption).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { store.errorMessage = nil }
                }.padding(12).background(.orange.opacity(0.08))
            }
        }.frame(width: 640, height: 540)
            .sheet(item: $editingRule) { rule in
                RuleEditor(rule: rule, destinations: store.destinations) { value in
                    store.update { config in
                        if let index = config.rules.firstIndex(where: { $0.id == value.id }) { config.rules[index] = value }
                        else { config.rules.append(value) }
                    }
                }
            }
            .alert("Could not open link", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
                Button("OK") { localError = nil }
            } message: { Text(localError ?? "") }
    }
    private var general: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default web browser").fontWeight(.medium)
                        Text(store.isDefault ? "External links come through Browser Picker." : "Set it once to choose where external links open.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.makingDefault ? "Working…" : store.isDefault ? "Refresh status" : "Make default…") { if store.isDefault { store.refreshStatus() } else { store.makeDefault() } }.disabled(store.makingDefault)
                }
                if let message = store.defaultBrowserSetupMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Button("Open System Settings…") { store.openDefaultBrowserSettings() }
                }
                Picker("For unmatched links", selection: Binding(get: { store.configuration.defaultDestinationID }, set: { value in store.update { $0.defaultDestinationID = value } })) {
                    Text("Always ask").tag("prompt")
                    ForEach(store.destinations) { Text($0.name).tag($0.id) }
                    if store.configuration.defaultDestinationID != "prompt" && !store.destinations.contains(where: { $0.id == store.configuration.defaultDestinationID }) {
                        Text("Unavailable browser — will ask").tag(store.configuration.defaultDestinationID)
                    }
                }
                Text("Hold Fn or Option when clicking a link to choose a browser, even when a rule matches.").font(.caption).foregroundStyle(.secondary)
                Toggle("Close picker when clicking outside", isOn: Binding(get: { store.configuration.dismissPickerOnOutsideClick }, set: { value in store.update { $0.dismissPickerOnOutsideClick = value } }))
                Toggle("Launch at login", isOn: Binding(get: { store.loginEnabled }, set: { store.setLogin($0) }))
                if store.loginRequiresApproval {
                    Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            Section {
                Toggle("Unwrap known redirect links", isOn: Binding(get: { store.configuration.unwrapRedirects }, set: { value in store.update { $0.unwrapRedirects = value } }))
                Toggle("Remove common tracking parameters", isOn: Binding(get: { store.configuration.cleanTracking }, set: { value in store.update { $0.cleanTracking = value } }))
                Text("Local processing only. Signed and authentication links keep their parameters.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Try the picker") {
                HStack {
                    TextField("https://example.com", text: $testURL).textFieldStyle(.roundedBorder).onSubmit { test() }
                    Button("Try link") { test() }
                }
            }
        }.formStyle(.grouped)
    }
    private var browsers: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shown in the picker and menu bar").font(.headline)
            Text("Browsers found by macOS and available profiles. Numbers follow this order.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.destinations) { destination in
                        HStack(spacing: 12) {
                            if let icon = store.icons[destination.appPath] { Image(nsImage: icon).resizable().frame(width: 32, height: 32) }
                            Toggle(destination.name, isOn: Binding(get: { !store.configuration.hiddenDestinationIDs.contains(destination.id) }, set: { visible in
                                store.update { config in
                                    if visible { config.hiddenDestinationIDs.remove(destination.id) }
                                    else if store.shownDestinations.count > 1 { config.hiddenDestinationIDs.insert(destination.id) }
                                }
                            })).toggleStyle(.checkbox)
                            Spacer()
                            if destination.supportsPrivate { Text("Private supported").font(.caption).foregroundStyle(.secondary) }
                            if destination.profile == nil && store.configuration.customBrowserPaths.contains(destination.appPath) {
                                Button { store.forgetBrowserLocation(destination.appPath) } label: { Image(systemName: "minus.circle") }.help("Forget added location. Automatically detected browsers may remain.")
                            }
                        }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            HStack {
                Button("Refresh browsers") { store.refresh() }
                Button("Add browser…") { addBrowser() }
                Spacer()
                Text("Any macOS browser").font(.caption).foregroundStyle(.tertiary)
            }
        }.padding(20)
    }
    private var rules: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Open the right browser automatically").font(.headline)
                    Text("First matching rule wins. Website and source conditions both apply.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { editingRule = Rule() } label: { Label("Add rule", systemImage: "plus") }
            }
            if store.configuration.rules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text("No rules yet").font(.headline)
                    Text("Add one here, or remember a website from the picker.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(store.configuration.rules.enumerated()), id: \.element.id) { index, rule in
                            HStack(spacing: 10) {
                                Toggle("Enable rule", isOn: Binding(get: { rule.enabled }, set: { value in store.update { config in if let current = config.rules.firstIndex(where: { $0.id == rule.id }) { config.rules[current].enabled = value } } })).labelsHidden().toggleStyle(.checkbox)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rule.domain.isEmpty ? "Any link or file" + rule.pathPrefix : rule.domain + rule.pathPrefix).fontWeight(.medium)
                                    Text(description(rule)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0).help("Move earlier")
                                Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(index + 1 == store.configuration.rules.count).help("Move later")
                                Button("Edit") { editingRule = rule }
                                Button { store.update { $0.rules.removeAll { $0.id == rule.id } } } label: { Image(systemName: "trash") }.help("Delete rule")
                            }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }.padding(20)
    }
    private func description(_ rule: Rule) -> String {
        let name = rule.destinationID == "prompt" ? "Ask" : store.destinations.first(where: { $0.id == rule.destinationID })?.name ?? "Unavailable browser — will ask"
        return (rule.sourceBundleID.isEmpty ? "" : "From \(rule.sourceBundleID) → ") + name + (rule.privateWindow ? " (Private)" : "")
    }
    private func move(_ index: Int, by offset: Int) {
        store.update { if $0.rules.indices.contains(index), $0.rules.indices.contains(index + offset) { $0.rules.swapAt(index, index + offset) } }
    }
    private func test() {
        do { onTest(try OpenTarget.parse(testURL, allowBareHost: true)) }
        catch { localError = error.localizedDescription }
    }
    private func addBrowser() {
        let panel = NSOpenPanel(); panel.title = "Choose a browser"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { store.addBrowser(url) }
    }
}

struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: Rule
    let destinations: [Destination]
    let save: (Rule) -> Bool
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Routing rule").font(.title2.weight(.semibold))
            Form {
                TextField("Website", text: $rule.domain, prompt: Text("github.com (or leave blank)"))
                Toggle("Include subdomains", isOn: $rule.includeSubdomains)
                TextField("Path prefix", text: $rule.pathPrefix, prompt: Text("/team (optional)"))
                HStack {
                    TextField("Source app", text: $rule.sourceBundleID, prompt: Text("Any app"))
                    Button("Choose…") { chooseSource() }
                }
                Picker("Open in", selection: $rule.destinationID) {
                    Text("Ask in picker").tag("prompt")
                    ForEach(destinations) { Text($0.name).tag($0.id) }
                    if rule.destinationID != "prompt" && !destinations.contains(where: { $0.id == rule.destinationID }) {
                        Text("Unavailable browser").tag(rule.destinationID)
                    }
                }.onChange(of: rule.destinationID) { _, _ in if !supportsPrivate { rule.privateWindow = false } }
                Toggle("Private window", isOn: $rule.privateWindow).disabled(!supportsPrivate)
            }
            Text("Leave the website blank to match links and files from a source app. A path prefix matches the beginning of the URL path.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save rule") {
                    do {
                        if save(try rule.validated()) { dismiss() }
                        else { error = "The rule could not be saved. Check the settings file and try again." }
                    }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 480)
    }
    private var supportsPrivate: Bool { destinations.first { $0.id == rule.destinationID }?.supportsPrivate == true }
    private func chooseSource() {
        let panel = NSOpenPanel(); panel.title = "Choose the app you click links in"
        panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier { rule.sourceBundleID = id }
    }
}
