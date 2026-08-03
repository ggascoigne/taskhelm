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

    @Test func exportsNextTasksWithConfiguredAndClientFilters() async throws {
        let uuid = UUID()
        let runner = RecordingRunner(results: [
            ProcessResult(
                exitCode: 0,
                standardOutput: "( status:pending or status:waiting ) -WAITING\n",
                standardError: ""
            ),
            ProcessResult(
                exitCode: 0,
                standardOutput: """
                    [{"id":7,"uuid":"\(uuid.uuidString)","description":"Ship browser","status":"pending","urgency":12.4,"custom.score":9}]
                    """,
                standardError: ""
            ),
        ])
        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/task")),
            runner: runner
        )

        let tasks = try await client.tasks(
            matching: TaskQuery(view: .next, project: "TW Mac", tag: "focus", rawFilter: "priority:H or due:today")
        )

        #expect(tasks.first?.uuid == uuid)
        #expect(tasks.first?.description == "Ship browser")
        #expect(tasks.first?.urgency == 12.4)
        #expect(tasks.first?.fields["custom.score"] == .number(9))
        #expect(runner.invocations[1].arguments == [
            "rc.json.array=on",
            "(",
            "status:pending",
            "or",
            "status:waiting",
            ")",
            "-WAITING",
            "-PARENT",
            "project:TW Mac",
            "+focus",
            "priority:H",
            "or",
            "due:today",
            "export",
        ])
    }

    @Test func preservesQuotedFilterTermsWithoutUsingAShell() throws {
        #expect(try TaskwarriorClient<RecordingRunner>.filterArguments(in: "project:'Big Work' +next") == [
            "project:Big Work",
            "+next",
        ])
        #expect(throws: TaskwarriorError.invalidFilter("unterminated quote")) {
            try TaskwarriorClient<RecordingRunner>.filterArguments(in: "project:'Big Work")
        }
    }

    @Test func readsPriorityOrderIncludingTheConfiguredBlankPosition() async throws {
        let runner = RecordingRunner(results: [
            ProcessResult(exitCode: 0, standardOutput: "H,M,,L\n", standardError: "")
        ])
        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/task")),
            runner: runner
        )

        #expect(try await client.priorityValues() == ["H", "M", "", "L"])
        #expect(runner.invocations.first?.arguments == ["_get", "rc.uda.priority.values"])
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
