# ResolutionHopper — specification

**Tagline:** Switch any display to a saved resolution and refresh rate from the menu bar, or let a profile do it for you.

**Category:** Display & Brightness

**Inspired by (paid):** SwitchResX ($16 one-time)

**Frameworks:** SwiftUI, AppKit, CoreGraphics, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: SwitchResX gives fine control over display resolutions and refresh rates, with menu bar switching and saved sets, and sells for about sixteen dollars as shareware. It has a long history of recommendations in Mac forums for people with external monitors, projectors and capture cards who need quick resolution changes that System Settings buries.

Our clean-room feature set: a menu bar list of every connected display, each with a submenu of all available display modes grouped by resolution and sorted by refresh rate, with HiDPI modes marked. The current mode shows a checkmark. Users can save the present state of all displays as a named profile, and apply a profile with one click or a hotkey. An optional automatic rule applies a profile when a specific display is connected. A Revert timer, like the system one, restores the previous mode after fifteen seconds unless confirmed. Around three hundred lines.

UI spec: MenuBarExtra in menu style. Top items list each display name with a submenu of modes. Below, a Profiles submenu with Apply entries, Save Current Layout and Manage. A settings window lists profiles with rename, delete and hotkey recorder fields, plus a toggle to show only HiDPI modes and a toggle for hidden low resolution modes. A confirmation sheet after switching shows a countdown with Keep and Revert buttons. Empty state: if only the built-in display exists, the menu still lists it and says no external displays connected.

Technical approach: enumerate active displays with CGGetActiveDisplayList. For each, call CGDisplayCopyAllDisplayModes with the option dictionary kCGDisplayShowDuplicateLowResolutionModes set to true to include HiDPI variants. Read width, height, pixel width, refresh rate and IO flags from CGDisplayMode. Apply a mode inside a CGBeginDisplayConfiguration and CGConfigureDisplayWithDisplayMode and CGCompleteDisplayConfiguration sequence using the permanent or session option. Identify displays across reconnects by CGDisplayVendorNumber, model number and serial number rather than the display id. Profiles are stored as JSON in Application Support. Display reconfiguration callbacks registered with CGDisplayRegisterReconfigurationCallback trigger the automatic rules. Hotkeys use RegisterEventHotKey from Carbon, which needs no permission. Launch at login uses SMAppService.

Edge cases: when a profile refers to a display that is not connected, skip that entry and report it in the menu. Mirrored displays must be handled by applying the mode to the primary of the mirror set. If applying a mode fails, show an alert with the error code and keep the previous state. The revert timer must still work if the display goes black, so it runs from a main-queue timer independent of window visibility. Filter modes flagged as not usable for desktop and skip stretched modes unless the user enables them. Debounce reconfiguration callbacks because they fire several times for one change.
