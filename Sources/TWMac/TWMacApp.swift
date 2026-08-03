import AppKit
import SwiftUI

@main
struct TWMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("TW Mac", systemImage: "checkmark.circle") {
            MenuBarContent(model: model, launchAtLogin: model.launchAtLogin)
        }
        .menuBarExtraStyle(.menu)

        Window("Task Browser", id: "task-browser") {
            TaskBrowserRootView(settings: model.settings)
                .frame(minWidth: 960, minHeight: 600)
        }
        .commands { TaskBrowserMenuCommands() }
        .defaultSize(width: 1_220, height: 760)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Task Browser") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "task-browser")
        }
        .keyboardShortcut("b")

        Button("Quick Capture") {
            model.showQuickCapture()
        }
        .keyboardShortcut("n")

        Divider()

        Button("Settings…") {
            model.showSettings()
        }

        Divider()

        Button("Quit TW Mac") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
