import Foundation
import Testing
@testable import TWMacCore

@Suite("Taskwarrior client")
struct TaskwarriorClientTests {
    @Test func createsLiteralDescriptionWithStructuredModifiers() async throws {
        let uuid = UUID()
        let runner = RecordingRunner(results: [
            ProcessResult(exitCode: 0, standardOutput: "Created task \(uuid.uuidString).\n", standardError: "")
        ])
        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/task")),
            runner: runner
        )

        let result = try await client.createTask(
            from: QuickCaptureDraft(
                description: "project:literal +not-a-tag",
                project: "northstar",
                tags: ["work", "next"],
                due: "tomorrow",
                priority: "H"
            )
        )

        #expect(result.uuid == uuid)
        #expect(runner.invocations.first?.arguments == [
            "rc.verbose=new-uuid",
            "rc.confirmation=off",
            "add",
            "project:northstar",
            "+work",
            "+next",
            "due:tomorrow",
            "priority:H",
            "--",
            "project:literal +not-a-tag",
        ])
    }

    @Test func rejectsOldTaskwarriorVersions() async {
        let runner = RecordingRunner(results: [
            ProcessResult(exitCode: 0, standardOutput: "3.3.0\n", standardError: "")
        ])
        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/task")),
            runner: runner
        )

        await #expect(throws: TaskwarriorError.unsupportedVersion(found: "3.3.0", minimum: "3.4.0")) {
            try await client.validateInstallation()
        }
    }
}

private final class RecordingRunner: ProcessRunning, @unchecked Sendable {
    struct Invocation {
        var executableURL: URL
        var arguments: [String]
        var environment: [String: String]
    }

    private let lock = NSLock()
    private var results: [ProcessResult]
    private(set) var invocations: [Invocation] = []

    init(results: [ProcessResult]) {
        self.results = results
    }

    func run(executableURL: URL, arguments: [String], environment: [String: String]) throws -> ProcessResult {
        lock.lock()
        defer { lock.unlock() }
        invocations.append(Invocation(executableURL: executableURL, arguments: arguments, environment: environment))
        return results.removeFirst()
    }
}
