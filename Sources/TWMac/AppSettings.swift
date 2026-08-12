import Foundation
import TWMacCore

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let taskExecutablePath = "taskExecutablePath"
        static let taskRCPath = "taskRCPath"
        static let capturesSelectedText = "capturesSelectedText"
        static let quickCaptureShortcut = "quickCaptureShortcut"
        static let taskBrowserShortcut = "taskBrowserShortcut"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    @Published var taskExecutablePath: String {
        didSet { defaults.set(taskExecutablePath, forKey: Key.taskExecutablePath) }
    }

    @Published var taskRCPath: String {
        didSet { defaults.set(taskRCPath, forKey: Key.taskRCPath) }
    }

    @Published var capturesSelectedText: Bool {
        didSet { defaults.set(capturesSelectedText, forKey: Key.capturesSelectedText) }
    }

    @Published var quickCaptureShortcut: GlobalShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(quickCaptureShortcut) {
                defaults.set(data, forKey: Key.quickCaptureShortcut)
            }
        }
    }

    @Published var taskBrowserShortcut: GlobalShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(taskBrowserShortcut) {
                defaults.set(data, forKey: Key.taskBrowserShortcut)
            }
        }
    }

    private let defaults: UserDefaults

    var needsOnboarding: Bool {
        !defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        taskExecutablePath = defaults.string(forKey: Key.taskExecutablePath) ?? Self.detectTaskExecutable()
        taskRCPath = defaults.string(forKey: Key.taskRCPath) ?? ""
        capturesSelectedText = defaults.object(forKey: Key.capturesSelectedText) as? Bool ?? false
        let storedQuickCaptureShortcut = defaults.data(forKey: Key.quickCaptureShortcut)
            .flatMap { try? JSONDecoder().decode(GlobalShortcut.self, from: $0) }
        quickCaptureShortcut = storedQuickCaptureShortcut == .legacyDefaultQuickCapture
            ? .defaultQuickCapture
            : storedQuickCaptureShortcut ?? .defaultQuickCapture
        taskBrowserShortcut = defaults.data(forKey: Key.taskBrowserShortcut)
            .flatMap { try? JSONDecoder().decode(GlobalShortcut.self, from: $0) }
            ?? .defaultTaskBrowser

        if storedQuickCaptureShortcut == .legacyDefaultQuickCapture,
           let data = try? JSONEncoder().encode(GlobalShortcut.defaultQuickCapture) {
            defaults.set(data, forKey: Key.quickCaptureShortcut)
        }
    }

    var taskwarriorEnvironment: TaskwarriorEnvironment {
        TaskwarriorEnvironment(
            executableURL: URL(fileURLWithPath: NSString(string: taskExecutablePath).expandingTildeInPath),
            taskRCURL: taskRCPath.isEmpty
                ? nil
                : URL(fileURLWithPath: NSString(string: taskRCPath).expandingTildeInPath)
        )
    }

    func completeOnboarding() {
        defaults.set(true, forKey: Key.hasCompletedOnboarding)
    }

    private static func detectTaskExecutable() -> String {
        let candidates = ["/opt/homebrew/bin/task", "/usr/local/bin/task", "/usr/bin/task"]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)) ?? "/opt/homebrew/bin/task"
    }
}
