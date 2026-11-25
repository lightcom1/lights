import AppKit
import SwiftUI

@main
struct LEDControlApp: App {
    @StateObject private var engine = Engine()

    init() {
        // allow `swift run` from Terminal to show a normal window with a Dock icon
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("LED control") {
            ContentView(engine: engine, strip: engine.strip)
                .frame(minWidth: 760, minHeight: 640)
                .preferredColorScheme(.dark)
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .windowResizability(.contentMinSize)
    }
}
