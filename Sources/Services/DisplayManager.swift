import AppKit
import CoreGraphics

/// One display mode as reported by CoreGraphics, with the attributes shown in the menu and used for matching.
struct DisplayModeInfo: Identifiable, Hashable {
    let mode: CGDisplayMode
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let ioModeID: Int32
    let ioFlags: UInt32

    init(_ mode: CGDisplayMode) {
        self.mode = mode
        width = mode.width
        height = mode.height
        pixelWidth = mode.pixelWidth
        pixelHeight = mode.pixelHeight
        refreshRate = mode.refreshRate
        ioModeID = mode.ioDisplayModeID
        ioFlags = mode.ioFlags
    }

    var id: String { "\(ioModeID)-\(width)x\(height)-\(pixelWidth)x\(pixelHeight)-\(refreshRate)" }
    var isHiDPI: Bool { pixelWidth > width }
    /// `kDisplayModeStretchedFlag` from IOGraphicsTypes.h.
    var isStretched: Bool { ioFlags & 0x0000_0800 != 0 }
    var isUsable: Bool { mode.isUsableForDesktopGUI() }

    var refreshLabel: String {
        if refreshRate <= 0 { return "default refresh" }
        return refreshRate == refreshRate.rounded() ? "\(Int(refreshRate)) Hz" : String(format: "%.2f Hz", refreshRate)
    }

    var title: String {
        var text = "\(width) × \(height) @ \(refreshLabel)"
        if isHiDPI { text += "  · HiDPI" }
        if isStretched { text += "  · stretched" }
        return text
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A group of modes that share the same resolution, sorted by refresh rate.
struct ModeGroup: Identifiable {
    let id: String
    let modes: [DisplayModeInfo]
}

/// A connected display: identity that survives reconnects plus its available and current modes.
struct DisplayInfo: Identifiable {
    let id: CGDirectDisplayID
    /// Display that modes are actually applied to (primary of a mirror set, or itself).
    let targetID: CGDirectDisplayID
    let key: String
    let name: String
    let isBuiltin: Bool
    let isMirrored: Bool
    let allModes: [DisplayModeInfo]
    let currentModeID: String?

    var menuTitle: String { isMirrored ? "\(name) (mirrored)" : name }

    /// Modes filtered by the user's preferences and grouped by resolution.
    func groupedModes(onlyHiDPI: Bool, showLowRes: Bool, showStretched: Bool) -> [ModeGroup] {
        let hiDPISizes = Set(allModes.filter(\.isHiDPI).map { "\($0.width)x\($0.height)" })
        let visible = allModes.filter { mode in
            if mode.id == currentModeID { return true }
            guard mode.isUsable else { return false }
            if mode.isStretched && !showStretched { return false }
            if onlyHiDPI && !mode.isHiDPI { return false }
            if !showLowRes && !mode.isHiDPI && hiDPISizes.contains("\(mode.width)x\(mode.height)") { return false }
            return true
        }
        let grouped = Dictionary(grouping: visible) { "\($0.width)x\($0.height)-\($0.pixelWidth)-\($0.isStretched)" }
        return grouped.map { key, modes in
            ModeGroup(id: key, modes: modes.sorted { $0.refreshRate > $1.refreshRate })
        }.sorted { a, b in
            let x = a.modes[0], y = b.modes[0]
            if x.width != y.width { return x.width > y.width }
            if x.height != y.height { return x.height > y.height }
            return x.pixelWidth > y.pixelWidth
        }
    }
}

/// Enumerates displays, applies modes through CoreGraphics and reports (debounced) reconfigurations.
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    /// Called with the identity keys of displays that appeared since the last refresh.
    var onConnected: (([String]) -> Void)?
    private var pendingRefresh: DispatchWorkItem?

    init() {
        refresh(notify: false)
        let callback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
            guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
            let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { manager.scheduleRefresh() }
        }
        CGDisplayRegisterReconfigurationCallback(callback, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Reconfiguration callbacks fire several times per change, so coalesce them.
    func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh(notify: true) }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func refresh(notify: Bool = false) {
        let previousKeys = Set(displays.map(\.key))
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { displays = []; return }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return }
        displays = ids.prefix(Int(count)).map(Self.makeInfo)
        let added = displays.map(\.key).filter { !previousKeys.contains($0) }
        if notify && !added.isEmpty { onConnected?(added) }
    }

    private static func makeInfo(_ id: CGDirectDisplayID) -> DisplayInfo {
        let mirrored = CGDisplayIsInMirrorSet(id) != 0
        let target = mirrored ? CGDisplayPrimaryDisplay(id) : id
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let raw = (CGDisplayCopyAllDisplayModes(target, options) as? [CGDisplayMode]) ?? []
        let current = CGDisplayCopyDisplayMode(target).map { DisplayModeInfo($0).id }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        let builtin = CGDisplayIsBuiltin(id) != 0
        return DisplayInfo(
            id: id, targetID: target, key: identityKey(id),
            name: screen?.localizedName ?? (builtin ? "Built-in Display" : "Display \(id)"),
            isBuiltin: builtin, isMirrored: mirrored && target != id,
            allModes: raw.map(DisplayModeInfo.init), currentModeID: current)
    }

    /// Vendor/model/serial identify a monitor across reconnects, unlike the display ID.
    static func identityKey(_ id: CGDirectDisplayID) -> String {
        "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    /// Current mode of every active display, used to revert a change.
    func snapshot() -> [(CGDirectDisplayID, CGDisplayMode)] {
        var seen = Set<CGDirectDisplayID>()
        return displays.compactMap { d in
            guard seen.insert(d.targetID).inserted, let mode = CGDisplayCopyDisplayMode(d.targetID) else { return nil }
            return (d.targetID, mode)
        }
    }

    /// Applies all changes in one configuration transaction; on failure nothing changes.
    func apply(_ changes: [(CGDirectDisplayID, CGDisplayMode)]) -> CGError {
        let permanent = UserDefaults.standard.object(forKey: "applyPermanently") as? Bool ?? true
        var config: CGDisplayConfigRef?
        var err = CGBeginDisplayConfiguration(&config)
        guard err == .success, let config else { return err }
        for (id, mode) in changes {
            err = CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
            if err != .success {
                CGCancelDisplayConfiguration(config)
                return err
            }
        }
        err = CGCompleteDisplayConfiguration(config, permanent ? .permanently : .forSession)
        return err
    }
}
