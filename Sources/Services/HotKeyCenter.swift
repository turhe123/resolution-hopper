import AppKit
import Carbon

/// Registers global hotkeys with Carbon's RegisterEventHotKey (no Accessibility permission needed).
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false

    func register(_ items: [(HotKey, () -> Void)]) {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
        installHandler()
        for (index, item) in items.enumerated() {
            let hotKeyID = EventHotKeyID(signature: OSType(0x5248_4F50), id: UInt32(index + 1))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(item.0.keyCode, item.0.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[hotKeyID.id] = item.1
            }
        }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if status == noErr {
                DispatchQueue.main.async { HotKeyCenter.shared.actions[hotKeyID.id]?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }

    /// Converts AppKit modifier flags to the Carbon mask expected by RegisterEventHotKey.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    static func symbols(_ flags: NSEvent.ModifierFlags) -> String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
    }
}
