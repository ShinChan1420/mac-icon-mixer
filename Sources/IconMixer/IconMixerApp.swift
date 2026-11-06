import SwiftUI

@main
struct IconMixerApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = MixerModel()

    var body: some Scene {
        Window("Icon Mixer", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
