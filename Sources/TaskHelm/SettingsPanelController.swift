import AppKit
import SwiftUI

@MainActor
final class SettingsPanelController: NSWindowController {
    static let contentSize = NSSize(width: 560, height: 500)

    private let settings: AppSettings
    private let launchAtLogin: LaunchAtLoginController
    private let requestAccessibilityPermission: () -> Void
    private var shortcutError: String?

    init(
        settings: AppSettings,
        launchAtLogin: LaunchAtLoginController,
        requestAccessibilityPermission: @escaping () -> Void
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.requestAccessibilityPermission = requestAccessibilityPermission
        super.init(window: Self.makePanel())
        updateContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let panel = window as? NSPanel else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            Self.center(panel, in: visibleFrame)
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func update(shortcutError: String?) {
        guard self.shortcutError != shortcutError else { return }
        self.shortcutError = shortcutError
        updateContent()
    }

    static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "TaskHelm Settings"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    static func center(_ panel: NSPanel, in visibleFrame: NSRect) {
        panel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - panel.frame.width / 2,
                y: visibleFrame.midY - panel.frame.height / 2
            )
        )
    }

    private func updateContent() {
        contentViewController = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                launchAtLogin: launchAtLogin,
                shortcutError: shortcutError,
                requestAccessibilityPermission: requestAccessibilityPermission
            )
        )
    }
}
