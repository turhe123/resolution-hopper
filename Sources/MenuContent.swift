import SwiftUI

/// The menu bar menu: displays with their modes, profiles, settings and support.
struct MenuContent: View {
    @ObservedObject var state: AppState
    @ObservedObject var displays: DisplayManager
    @ObservedObject var profiles: ProfileStore
    @AppStorage("onlyHiDPI") private var onlyHiDPI = false
    @AppStorage("showLowRes") private var showLowRes = false
    @AppStorage("showStretched") private var showStretched = false

    var body: some View {
        ForEach(displays.displays) { display in
            Menu(display.menuTitle) {
                let groups = display.groupedModes(onlyHiDPI: onlyHiDPI, showLowRes: showLowRes, showStretched: showStretched)
                if groups.isEmpty { Text("No modes match the current filters") }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.modes) { mode in
                            Toggle(mode.title, isOn: Binding(
                                get: { display.currentModeID == mode.id },
                                set: { _ in state.switchMode(mode, on: display) }))
                        }
                    }
                }
            }
        }
        if !displays.displays.contains(where: { !$0.isBuiltin }) {
            Text("No external displays connected")
        }
        if let message = state.statusMessage {
            Text(message)
        }

        Divider()
        Menu("Profiles") {
            if profiles.profiles.isEmpty { Text("No saved profiles") }
            ForEach(profiles.profiles) { profile in
                Button("Apply “\(profile.name)”" + (profile.hotKey.map { "   \($0.display)" } ?? "")) {
                    state.applyProfile(profile)
                }
            }
            Divider()
            Button("Save Current Layout…") { state.promptSaveCurrentLayout() }
            SettingsLink { Text("Manage…") }
        }

        Divider()
        Button("Refresh Displays") { displays.refresh() }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Support / Donate ❤️") { state.openDonate() }
        Divider()
        Button("Quit ResolutionHopper") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
