import AppKit
import SwiftUI

@main
struct TWMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model, launchAtLogin: model.launchAtLogin)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        Window("Task Browser", id: "task-browser") {
            TaskBrowserRootView(settings: model.settings)
                .frame(minWidth: 960, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Quick Capture") {
                    model.showQuickCapture()
                }
                .keyboardShortcut(
                    model.settings.quickCaptureShortcut.menuKeyEquivalent,
                    modifiers: model.settings.quickCaptureShortcut.menuModifiers
                )
            }
            TaskBrowserMenuCommands()
        }
        .defaultSize(width: 1_220, height: 760)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label("TW Mac", systemImage: "checkmark.circle")
            .onAppear {
                model.configureTaskBrowserPresenter {
                    openWindow(id: "task-browser")
                }
            }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var launchAtLogin: LaunchAtLoginController

    var body: some View {
        Button("Task Browser") {
            model.showTaskBrowser()
        }
        .keyboardShortcut(
            model.settings.taskBrowserShortcut.menuKeyEquivalent,
            modifiers: model.settings.taskBrowserShortcut.menuModifiers
        )

        Button("Quick Capture") {
            model.showQuickCapture()
        }
        .keyboardShortcut(
            model.settings.quickCaptureShortcut.menuKeyEquivalent,
            modifiers: model.settings.quickCaptureShortcut.menuModifiers
        )

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
