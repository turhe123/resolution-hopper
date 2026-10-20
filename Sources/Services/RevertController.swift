import AppKit
import SwiftUI

/// Runs the 15-second "Keep or Revert" countdown after a mode switch.
/// The timer lives on the main run loop, so it fires even if the display goes black.
final class RevertController: ObservableObject {
    static let duration = 15
    @Published private(set) var remaining = duration
    private var timer: Timer?
    private var panel: NSPanel?
    private var revertAction: (() -> Void)?

    func start(revert: @escaping () -> Void) {
        finish()
        revertAction = revert
        remaining = Self.duration
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        showPanel()
    }

    func keep() { finish() }

    func revertNow() {
        let action = revertAction
        finish()
        action?()
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 { revertNow() }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        revertAction = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func showPanel() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "ResolutionHopper"
        panel.isReleasedWhenClosed = false
        panel.level = .modalPanel
        panel.contentView = NSHostingView(rootView: RevertView(controller: self))
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}

/// Confirmation content with countdown, Keep and Revert buttons.
struct RevertView: View {
    @ObservedObject var controller: RevertController

    var body: some View {
        VStack(spacing: 14) {
            Text("Keep this display mode?").font(.headline)
            Text("Reverting to the previous mode in \(controller.remaining) seconds.")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            HStack {
                Button("Revert") { controller.revertNow() }
                Button("Keep") { controller.keep() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360, height: 150)
    }
}
