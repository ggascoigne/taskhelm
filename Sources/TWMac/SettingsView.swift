import SwiftUI
import TWMacCore

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    let shortcutError: String?
    let requestAccessibilityPermission: () -> Void
    @State private var validationMessage: String?
    @State private var isValidating = false

    var body: some View {
        Form {
            Section("Taskwarrior") {
                TextField("Executable", text: $settings.taskExecutablePath)
                TextField("Optional taskrc", text: $settings.taskRCPath)

                HStack {
                    Button("Validate") {
                        validate()
                    }
                    .disabled(isValidating)

                    if isValidating {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let validationMessage {
                        Text(validationMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Quick Capture") {
                LabeledContent("Global shortcut") {
                    ShortcutRecorderView(shortcut: $settings.quickCaptureShortcut)
                        .frame(width: 120, height: 28)
                }

                if let shortcutError {
                    Label(shortcutError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Toggle("Seed Description from selected text", isOn: $settings.capturesSelectedText)
                    .onChange(of: settings.capturesSelectedText) { _, enabled in
                        if enabled { requestAccessibilityPermission() }
                    }

                if settings.capturesSelectedText {
                    Text("TW Mac must be enabled in System Settings → Privacy & Security → Accessibility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )

                if let errorMessage = launchAtLogin.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(
            width: SettingsPanelController.contentSize.width,
            height: SettingsPanelController.contentSize.height
        )
    }

    private func validate() {
        isValidating = true
        validationMessage = nil
        let client = TaskwarriorClient(
            environment: settings.taskwarriorEnvironment,
            runner: FoundationProcessRunner()
        )

        Task {
            defer { isValidating = false }
            do {
                let installation = try await client.validateInstallation()
                validationMessage = "Taskwarrior \(installation.version)"
            } catch {
                validationMessage = error.localizedDescription
            }
        }
    }
}
