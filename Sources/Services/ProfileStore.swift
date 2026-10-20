import Foundation

/// A global keyboard shortcut stored as a Carbon key code and modifier mask.
struct HotKey: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String
}

/// The saved mode of one display within a profile.
struct ProfileEntry: Codable, Hashable {
    var displayKey: String
    var displayName: String
    var width: Int
    var height: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var refreshRate: Double

    init(display: DisplayInfo, mode: DisplayModeInfo) {
        displayKey = display.key
        displayName = display.name
        width = mode.width
        height = mode.height
        pixelWidth = mode.pixelWidth
        pixelHeight = mode.pixelHeight
        refreshRate = mode.refreshRate
    }

    func matches(_ mode: DisplayModeInfo) -> Bool {
        mode.width == width && mode.height == height && mode.pixelWidth == pixelWidth
            && mode.pixelHeight == pixelHeight && abs(mode.refreshRate - refreshRate) < 0.5
    }
}

/// A named layout of all displays, optionally bound to a hotkey or auto-applied on connect.
struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var entries: [ProfileEntry]
    var hotKey: HotKey?
    var autoApplyDisplayKey: String?
}

/// Loads and saves profiles as JSON in Application Support.
final class ProfileStore: ObservableObject {
    @Published var profiles: [Profile] = [] {
        didSet { if !isLoading { save(); onChange?() } }
    }
    var onChange: (() -> Void)?
    private var isLoading = false

    private var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("ResolutionHopper", isDirectory: true).appendingPathComponent("profiles.json")
    }

    init() { load() }

    private func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        isLoading = true
        profiles = (try? JSONDecoder().decode([Profile].self, from: data)) ?? []
        isLoading = false
    }

    private func save() {
        guard let url = fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(profiles).write(to: url, options: .atomic)
        } catch {
            NSLog("ResolutionHopper: failed to save profiles: \(error)")
        }
    }
}
