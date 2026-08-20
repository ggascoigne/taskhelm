import SwiftUI
import TaskHelmCore

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    let shortcutError: String?
    let requestAccessibilityPermission: () -> Void
    let complete: () -> Void

    @State private var validation: ValidationState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 42))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to TaskHelm")
                        .font(.title.bold())
                    Text("A native interface for your existing Taskwarrior workflow.")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Taskwarrior") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Executable", text: $settings.taskExecutablePath)
                        .onSubmit { validate() }
                    TextField("Optional taskrc", text: $settings.taskRCPath)
                        .onSubmit { validate() }

                    HStack(spacing: 8) {
                        Button("Validate", action: validate)
                            .disabled(validation.isRunning)
                        validationLabel
                    }
                }
                .padding(6)
            }

            GroupBox("Shortcuts & Quick Capture") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("New Task") {
                        ShortcutRecorderView(shortcut: $settings.quickCaptureShortcut)
                            .frame(width: 130, height: 28)
                    }

                    LabeledContent("Task Browser") {
                        ShortcutRecorderView(shortcut: $settings.taskBrowserShortcut)
                            .frame(width: 130, height: 28)
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

                    Text("Selected-text capture uses macOS Accessibility access. TaskHelm requests permission only when this option is enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }

            GroupBox("Startup") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        "Launch TaskHelm at Login (Recommended)",
                        isOn: Binding(
                            get: { launchAtLogin.isEnabled },
                            set: { launchAtLogin.setEnabled($0) }
                        )
                    )
                    Text("TaskHelm lives in the menu bar, so launching it at login keeps Quick Capture available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let errorMessage = launchAtLogin.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(6)
            }

            HStack {
                Text("These options remain available in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Finish Setup", action: complete)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!validation.isValid || shortcutError != nil)
            }
        }
        .padding(24)
        .frame(width: OnboardingPanelController.contentSize.width, height: OnboardingPanelController.contentSize.height)
        .task { await validateNow() }
    }

    @ViewBuilder
    private var validationLabel: some View {
        switch validation {
        case .idle:
            EmptyView()
        case .validating:
            ProgressView()
                .controlSize(.small)
        case let .valid(version):
            Label("Taskwarrior \(version)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .invalid(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func validate() {
        Task { await validateNow() }
    }

    private func validateNow() async {
        validation = .validating
        let client = TaskwarriorClient(
            environment: settings.taskwarriorEnvironment,
            runner: FoundationProcessRunner()
        )
        do {
            validation = .valid((try await client.validateInstallation()).version)
        } catch {
            validation = .invalid(error.localizedDescription)
        }
    }
}

private enum ValidationState: Equatable {
    case idle
    case validating
    case valid(String)
    case invalid(String)

    var isRunning: Bool { self == .validating }

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}
