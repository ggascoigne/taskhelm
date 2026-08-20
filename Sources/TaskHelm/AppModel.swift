import AppKit
import Combine
import TaskHelmCore

@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let launchAtLogin: LaunchAtLoginController
    @Published private(set) var shortcutRegistrationError: String?

    private var capturePanel: QuickCapturePanelController?
    private var settingsPanel: SettingsPanelController?
    private var onboardingPanel: OnboardingPanelController?
    private var quickCaptureHotKeyManager: GlobalHotKeyManager?
    private var taskBrowserHotKeyManager: GlobalHotKeyManager?
    private var quickCaptureShortcutError: String?
    private var taskBrowserShortcutError: String?
    private var taskBrowserPresenter: (() -> Void)?
    private var cancellables: Set<AnyCancellable> = []
    private let selectedTextReader = SelectedTextReader()

    convenience init() {
        self.init(settings: AppSettings(), launchAtLogin: LaunchAtLoginController())
    }

    init(settings: AppSettings, launchAtLogin: LaunchAtLoginController) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        capturePanel = QuickCapturePanelController(
            makeViewModel: { [weak self] in
                guard let self else { fatalError("AppModel released while presenting Quick Capture") }
                return QuickCaptureViewModel(
                    client: TaskwarriorClient(
                        environment: self.settings.taskwarriorEnvironment,
                        runner: FoundationProcessRunner()
                    ),
                    onCancel: { [weak self] in self?.capturePanel?.dismiss() },
                    onCreated: { [weak self] in self?.capturePanel?.dismiss() }
                )
            },
            onShowTaskBrowser: { [weak self] in self?.showTaskBrowser() }
        )

        quickCaptureHotKeyManager = GlobalHotKeyManager(identifier: 1) { [weak self] in
            self?.showQuickCapture()
        }
        taskBrowserHotKeyManager = GlobalHotKeyManager(identifier: 2) { [weak self] in
            self?.showTaskBrowser()
        }
        registerQuickCaptureShortcut(settings.quickCaptureShortcut)
        registerTaskBrowserShortcut(settings.taskBrowserShortcut)
        if settings.capturesSelectedText {
            requestAccessibilityPermission()
        }
        settings.$quickCaptureShortcut
            .dropFirst()
            .sink { [weak self] shortcut in
                self?.registerQuickCaptureShortcut(shortcut)
            }
            .store(in: &cancellables)
        settings.$taskBrowserShortcut
            .dropFirst()
            .sink { [weak self] shortcut in
                self?.registerTaskBrowserShortcut(shortcut)
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

    func showQuickCapture(description: String = "", includeSelectedText: Bool = true) {
        let latencyTrace = QuickCaptureLatency.begin()
        guard includeSelectedText, description.isEmpty, settings.capturesSelectedText else {
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

    func configureTaskBrowserPresenter(_ presenter: @escaping () -> Void) {
        taskBrowserPresenter = presenter
    }

    func showTaskBrowser() {
        capturePanel?.dismiss()
        if let window = TaskBrowserWindowPlacement.browserWindow() {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            TaskBrowserWindowPlacement.moveToActiveDesktop(window)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        taskBrowserPresenter?()
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

    private func registerQuickCaptureShortcut(_ shortcut: GlobalShortcut) {
        do {
            try quickCaptureHotKeyManager?.register(shortcut)
            quickCaptureShortcutError = nil
        } catch {
            quickCaptureShortcutError = "New Task: \(error.localizedDescription)"
        }
        updateShortcutRegistrationError()
    }

    private func registerTaskBrowserShortcut(_ shortcut: GlobalShortcut) {
        do {
            try taskBrowserHotKeyManager?.register(shortcut)
            taskBrowserShortcutError = nil
        } catch {
            taskBrowserShortcutError = "Task Browser: \(error.localizedDescription)"
        }
        updateShortcutRegistrationError()
    }

    private func updateShortcutRegistrationError() {
        shortcutRegistrationError = [quickCaptureShortcutError, taskBrowserShortcutError]
            .compactMap { $0 }
            .joined(separator: "\n")
        if shortcutRegistrationError?.isEmpty == true { shortcutRegistrationError = nil }
        settingsPanel?.update(shortcutError: shortcutRegistrationError)
        onboardingPanel?.update(shortcutError: shortcutRegistrationError)
    }
}
