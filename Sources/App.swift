import AppKit
import CoreGraphics
import SwiftUI

/// Entry point: a menu-bar-only app with a Settings window.
@main
struct ResolutionHopperApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("ResolutionHopper", systemImage: "display") {
            MenuContent(state: state, displays: state.displays, profiles: state.profiles)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(state: state, displays: state.displays, profiles: state.profiles)
        }
    }
}

/// Coordinates displays, profiles, hotkeys, automatic rules and the revert timer.
final class AppState: ObservableObject {
    static let shared = AppState()

    let displays = DisplayManager()
    let profiles = ProfileStore()
    let revert = RevertController()
    @Published var statusMessage: String?

    init() {
        displays.onConnected = { [weak self] keys in self?.autoApply(connected: keys) }
        profiles.onChange = { [weak self] in self?.registerHotKeys() }
        registerHotKeys()
    }

    func openDonate() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }

    // MARK: Switching

    func switchMode(_ mode: DisplayModeInfo, on display: DisplayInfo) {
        guard display.currentModeID != mode.id else { return }
        perform([(display.targetID, mode.mode)], confirm: true)
    }

    func applyProfile(_ profile: Profile, confirm: Bool = true) {
        var changes: [(CGDirectDisplayID, CGDisplayMode)] = []
        var skipped: [String] = []
        var targets = Set<CGDirectDisplayID>()
        for entry in profile.entries {
            guard let display = displays.displays.first(where: { $0.key == entry.displayKey }),
                  let mode = display.allModes.first(where: entry.matches) else {
                skipped.append(entry.displayName)
                continue
            }
            if display.currentModeID != mode.id, targets.insert(display.targetID).inserted {
                changes.append((display.targetID, mode.mode))
            }
        }
        statusMessage = skipped.isEmpty
            ? "Applied “\(profile.name)”"
            : "“\(profile.name)”: skipped \(skipped.joined(separator: ", ")) (not connected)"
        perform(changes, confirm: confirm)
    }

    private func perform(_ changes: [(CGDirectDisplayID, CGDisplayMode)], confirm: Bool) {
        guard !changes.isEmpty else { return }
        let previous = displays.snapshot()
        let err = displays.apply(changes)
        displays.refresh()
        guard err == .success else { showError(err); return }
        guard confirm else { return }
        revert.start { [weak self] in
            guard let self else { return }
            let online = Set(self.displays.displays.map(\.targetID))
            let result = self.displays.apply(previous.filter { online.contains($0.0) })
            self.displays.refresh()
            if result != .success { self.showError(result) }
        }
    }

    private func showError(_ err: CGError) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t switch display mode"
        alert.informativeText = "CoreGraphics returned error \(err.rawValue). The previous mode was kept."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: Profiles

    func saveCurrentLayout(named name: String) {
        let entries = displays.displays.compactMap { display -> ProfileEntry? in
            guard let mode = display.allModes.first(where: { $0.id == display.currentModeID }) else { return nil }
            return ProfileEntry(display: display, mode: mode)
        }
        profiles.profiles.append(Profile(name: name, entries: entries))
        statusMessage = "Saved “\(name)”"
    }

    func promptSaveCurrentLayout() {
        let alert = NSAlert()
        alert.messageText = "Save Current Layout"
        alert.informativeText = "Name this profile. It stores the current mode of every connected display."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = "Profile \(profiles.profiles.count + 1)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        saveCurrentLayout(named: name.isEmpty ? "Untitled" : name)
    }

    private func registerHotKeys() {
        let items = profiles.profiles.compactMap { profile -> (HotKey, () -> Void)? in
            guard let hotKey = profile.hotKey else { return nil }
            let id = profile.id
            return (hotKey, { [weak self] in
                guard let self, let current = self.profiles.profiles.first(where: { $0.id == id }) else { return }
                self.applyProfile(current)
            })
        }
        HotKeyCenter.shared.register(items)
    }

    /// Automatic rules: apply any profile bound to a display that just connected.
    private func autoApply(connected keys: [String]) {
        for profile in profiles.profiles {
            if let key = profile.autoApplyDisplayKey, keys.contains(key) {
                applyProfile(profile, confirm: false)
            }
        }
    }
}
