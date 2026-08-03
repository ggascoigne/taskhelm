import AppKit
import SwiftUI

@MainActor
final class OnboardingPanelController: NSWindowController {
    static let contentSize = NSSize(width: 640, height: 620)

    private let settings: AppSettings
    private let launchAtLogin: LaunchAtLoginController
    private let requestAccessibilityPermission: () -> Void
    private let onComplete: () -> Void
    private var shortcutError: String?

    init(
        settings: AppSettings,
        launchAtLogin: LaunchAtLoginController,
        requestAccessibilityPermission: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.requestAccessibilityPermission = requestAccessibilityPermission
        self.onComplete = onComplete
        super.init(window: Self.makePanel())
        updateContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let panel = window as? NSPanel else { return }
        if let visibleFrame = NSScreen.main?.visibleFrame {
            SettingsPanelController.center(panel, in: visibleFrame)
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
        panel.title = "Welcome to TW Mac"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    private func updateContent() {
        contentViewController = NSHostingController(
            rootView: OnboardingView(
                settings: settings,
                launchAtLogin: launchAtLogin,
                shortcutError: shortcutError,
                requestAccessibilityPermission: requestAccessibilityPermission,
                complete: { [weak self] in self?.finish() }
            )
        )
    }

    private func finish() {
        settings.completeOnboarding()
        window?.orderOut(nil)
        onComplete()
    }
}
