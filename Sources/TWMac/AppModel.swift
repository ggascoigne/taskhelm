import AppKit
import Combine
import TWMacCore

@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let launchAtLogin: LaunchAtLoginController
    @Published private(set) var shortcutRegistrationError: String?

    private var capturePanel: QuickCapturePanelController?
    private var settingsPanel: SettingsPanelController?
    private var onboardingPanel: OnboardingPanelController?
    private var hotKeyManager: GlobalHotKeyManager?
    private var cancellables: Set<AnyCancellable> = []
    private let selectedTextReader = SelectedTextReader()

    convenience init() {
        self.init(settings: AppSettings(), launchAtLogin: LaunchAtLoginController())
    }

    init(settings: AppSettings, launchAtLogin: LaunchAtLoginController) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        capturePanel = QuickCapturePanelController { [weak self] in
            guard let self else { fatalError("AppModel released while presenting Quick Capture") }
            return QuickCaptureViewModel(
                client: TaskwarriorClient(
                    environment: self.settings.taskwarriorEnvironment,
                    runner: FoundationProcessRunner()
                ),
                onCancel: { [weak self] in self?.capturePanel?.dismiss() },
                onCreated: { [weak self] in self?.capturePanel?.dismiss() }
            )
        }

        hotKeyManager = GlobalHotKeyManager { [weak self] in
            self?.showQuickCapture()
        }
        registerShortcut(settings.quickCaptureShortcut)
        if settings.capturesSelectedText {
            requestAccessibilityPermission()
        }
        settings.$quickCaptureShortcut
            .dropFirst()
            .sink { [weak self] shortcut in
                self?.registerShortcut(shortcut)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didFinishLaunchingNotification)
            .prefix(1)
            .sink { [weak self] _ in
                self?.capturePanel?.prewarm()
                self?.showOnboarding()
            }
            .store(in: &cancellables)
    }

    func showQuickCapture(description: String = "") {
        let latencyTrace = QuickCaptureLatency.begin()
        guard description.isEmpty, settings.capturesSelectedText else {
            capturePanel?.present(description: description) {
                _ = QuickCaptureLatency.finish(latencyTrace, selectionLookup: nil)
            }
            return
        }

        Task {
            let selection = await selectedTextReader.selectedText() ?? ""
            let selectionDuration = QuickCaptureLatency.recordSelectionLookup(for: latencyTrace)
            capturePanel?.present(description: selection) {
                _ = QuickCaptureLatency.finish(latencyTrace, selectionLookup: selectionDuration)
            }
        }
    }

    func requestAccessibilityPermission() {
        _ = selectedTextReader.requestPermission()
    }

    func showSettings() {
        let controller = settingsPanel ?? SettingsPanelController(
            settings: settings,
            launchAtLogin: launchAtLogin,
            requestAccessibilityPermission: { [weak self] in self?.requestAccessibilityPermission() }
        )
        controller.update(shortcutError: shortcutRegistrationError)
        controller.present()
        settingsPanel = controller
    }

    private func showOnboarding() {
        guard settings.needsOnboarding else { return }
        let controller = onboardingPanel ?? OnboardingPanelController(
            settings: settings,
            launchAtLogin: launchAtLogin,
            requestAccessibilityPermission: { [weak self] in self?.requestAccessibilityPermission() },
            onComplete: { [weak self] in self?.onboardingPanel = nil }
        )
        controller.update(shortcutError: shortcutRegistrationError)
        controller.present()
        onboardingPanel = controller
    }

    private func registerShortcut(_ shortcut: GlobalShortcut) {
        do {
            try hotKeyManager?.register(shortcut)
            shortcutRegistrationError = nil
        } catch {
            shortcutRegistrationError = error.localizedDescription
        }
        settingsPanel?.update(shortcutError: shortcutRegistrationError)
        onboardingPanel?.update(shortcutError: shortcutRegistrationError)
    }
}
