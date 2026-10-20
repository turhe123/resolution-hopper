import ServiceManagement
import SwiftUI

/// Settings window: profile management, mode filters, launch at login and support.
struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var displays: DisplayManager
    @ObservedObject var profiles: ProfileStore
    @AppStorage("onlyHiDPI") private var onlyHiDPI = false
    @AppStorage("showLowRes") private var showLowRes = false
    @AppStorage("showStretched") private var showStretched = false
    @AppStorage("applyPermanently") private var applyPermanently = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Profiles") {
                if profiles.profiles.isEmpty {
                    Text("No profiles yet. Use “Save Current Layout…” in the menu bar.")
                        .foregroundStyle(.secondary)
                }
                ForEach($profiles.profiles) { $profile in
                    ProfileRow(profile: $profile, displays: displays.displays) {
                        profiles.profiles.removeAll { $0.id == profile.id }
                    }
                }
                Button("Save Current Layout…") { state.promptSaveCurrentLayout() }
            }
            Section("Modes") {
                Toggle("Show only HiDPI modes", isOn: $onlyHiDPI)
                Toggle("Show hidden low-resolution modes", isOn: $showLowRes)
                Toggle("Show stretched modes", isOn: $showStretched)
                Toggle("Keep mode changes after restart", isOn: $applyPermanently)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Button("Support / Donate ❤️") { state.openDonate() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn’t update login item: \(error.localizedDescription). Check System Settings › General › Login Items."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// One editable profile: name, hotkey, automatic rule and delete.
struct ProfileRow: View {
    @Binding var profile: Profile
    let displays: [DisplayInfo]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Name", text: $profile.name)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Delete profile")
            }
            Text(profile.entries.map { "\($0.displayName): \($0.width)×\($0.height)" }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Hotkey")
                HotKeyRecorder(hotKey: $profile.hotKey)
                Spacer()
                Picker("Auto-apply", selection: $profile.autoApplyDisplayKey) {
                    Text("Never").tag(String?.none)
                    ForEach(autoApplyChoices, id: \.key) { choice in
                        Text("When \(choice.name) connects").tag(String?.some(choice.key))
                    }
                }
                .fixedSize()
            }
        }
        .padding(.vertical, 4)
    }

    /// Connected external displays plus any displays this profile already references.
    private var autoApplyChoices: [(key: String, name: String)] {
        var choices = displays.filter { !$0.isBuiltin }.map { (key: $0.key, name: $0.name) }
        for entry in profile.entries where !choices.contains(where: { $0.key == entry.displayKey }) {
            choices.append((key: entry.displayKey, name: entry.displayName))
        }
        return choices
    }
}

/// Click-to-record field that captures the next key combination as a global hotkey.
struct HotKeyRecorder: View {
    @Binding var hotKey: HotKey?
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(monitor != nil ? "Type shortcut…" : (hotKey?.display ?? "Record")) {
                monitor == nil ? startRecording() : stopRecording()
            }
            .frame(minWidth: 90)
            if hotKey != nil {
                Button { hotKey = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help("Clear hotkey")
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53 { stopRecording(); return nil } // Escape cancels
            guard !flags.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return nil }
            let key = event.charactersIgnoringModifiers?.uppercased() ?? "?"
            hotKey = HotKey(keyCode: UInt32(event.keyCode),
                            modifiers: HotKeyCenter.carbonModifiers(flags),
                            display: HotKeyCenter.symbols(flags) + key)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
