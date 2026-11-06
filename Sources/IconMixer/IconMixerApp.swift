import SwiftUI

@main
struct IconMixerApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("Icon Mixer", id: "main") {
            ContentView(model: delegate.model)
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MixerModel()
    private var appearanceObservation: NSKeyValueObservation?

    /// Icons applied with the Auto tone can only follow the Mac's mode while the app runs.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !model.keepsIconsInSync
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        updateAppearance()
        model.syncAutoIcons()
        // Watches the app itself, so it still works with the window closed.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.updateAppearance() }
        }
    }

    private func updateAppearance() {
        model.systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
