import AppKit
import Combine
import TWMacCore

@MainActor
final class AppModel: ObservableObject {
    let settings = AppSettings()
    @Published private(set) var shortcutRegistrationError: String?

    private var capturePanel: QuickCapturePanelController?
    private var settingsPanel: SettingsPanelController?
    private var hotKeyManager: GlobalHotKeyManager?
    private var cancellables: Set<AnyCancellable> = []
    private let selectedTextReader = SelectedTextReader()

    init() {
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
    }

    func showQuickCapture(description: String = "") {
        guard description.isEmpty, settings.capturesSelectedText else {
            capturePanel?.present(description: description)
            return
        }

        Task {
            let selection = await selectedTextReader.selectedText() ?? ""
            capturePanel?.present(description: selection)
        }
    }

    func requestAccessibilityPermission() {
        _ = selectedTextReader.requestPermission()
    }

    func showSettings(launchAtLogin: LaunchAtLoginController) {
        let controller = settingsPanel ?? SettingsPanelController(
            settings: settings,
            launchAtLogin: launchAtLogin,
            requestAccessibilityPermission: { [weak self] in self?.requestAccessibilityPermission() }
        )
        controller.update(shortcutError: shortcutRegistrationError)
        controller.present()
        settingsPanel = controller
    }

    private func registerShortcut(_ shortcut: GlobalShortcut) {
        do {
            try hotKeyManager?.register(shortcut)
            shortcutRegistrationError = nil
        } catch {
            shortcutRegistrationError = error.localizedDescription
        }
        settingsPanel?.update(shortcutError: shortcutRegistrationError)
    }
}
