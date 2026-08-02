import AppKit
import SwiftUI

@main
struct TWMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    var body: some Scene {
        MenuBarExtra("TW Mac", systemImage: "checkmark.circle") {
            Button("Quick Capture") {
                model.showQuickCapture()
            }
            .keyboardShortcut("n")

            Divider()

            Button("Settings…") {
                model.showSettings(launchAtLogin: launchAtLogin)
            }

            Divider()

            Button("Quit TW Mac") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
