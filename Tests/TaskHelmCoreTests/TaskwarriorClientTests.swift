import Foundation
import Testing
@testable import TaskHelmCore

@Suite("Taskwarrior client")
struct TaskwarriorClientTests {
    @Test func replacesTheExactAnnotationWithANewTimestamp() async throws {
        let uuid = UUID()
        let original = TaskAnnotation(entry: "20260805T120000Z", description: "Original")
        let before = """
            [{"uuid":"\(uuid.uuidString)","description":"Write report","status":"pending","annotations":[{"entry":"20260805T120000Z","description":"Original"},{"entry":"20260805T130000Z","description":"Keep"}]}]
            """
        let after = """
            [{"uuid":"\(uuid.uuidString)","description":"Write report","status":"pending","annotations":[{"entry":"20260805T130000Z","description":"Keep"},{"entry":"20260805T140000Z","description":"Revised"}]}]
            """
        let runner = RecordingRunner(results: [
            ProcessResult(exitCode: 0, standardOutput: before, standardError: ""),
            ProcessResult(exitCode: 0, standardOutput: "Imported 1 task.", standardError: ""),
            ProcessResult(exitCode: 0, standardOutput: after, standardError: ""),
        ])
        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/task")),
            runner: runner
        )

        _ = try await client.perform(.replaceAnnotation(uuid, original, "Revised"))

        let invocation = runner.invocations[1]
        #expect(invocation.arguments == [
            "rc.context=", "rc.confirmation=off", "rc.recurrence.confirmation=no", "import", "-",
        ])
        let imported = try #require(invocation.standardInput)
        let records = try JSONDecoder().decode([[String: JSONValue]].self, from: imported)
        guard case let .array(annotationValues) = records.first?["annotations"] else {
            Issue.record("Replacement import did not contain annotations")
            return
        }
        let annotations = annotationValues.compactMap(TaskAnnotation.init(jsonValue:))
        #expect(annotations.contains(TaskAnnotation(entry: "20260805T130000Z", description: "Keep")))
        #expect(!annotations.contains(original))
        #expect(annotations.contains { $0.description == "Revised" && $0.entry != original.entry })
    }

    @Test func deletesTheExactAnnotation() async throws {
        let uuid = UUID()
        let deleted = TaskAnnotation(entry: "20260805T120000Z", description: "Duplicate text")
        let before = """
            [{"uuid":"\(uuid.uuidString)","description":"Write report","status":"pending","annotations":[{"entry":"20260805T120000Z","description":"Duplicate text"},{"entry":"20260805T130000Z","description":"Duplicate text"}]}]
            """
        let after = """
            [{"uuid":"\(uuid.uuidString)","description":"Write report","status":"pending","annotations":[{"entry":"20260805T130000Z","description":"Duplicate text"}]}]
            """
        let runner = RecordingRunner(results: [
            ProcessResult(exitCode: 0, standardOutput: before, standardError: ""),
            ProcessResult(exitCode: 0, standardOutput: "Imported 1 task.", standardError: ""),
            ProcessResult(exitCode: 0, standardOutput: after, standardError: ""),
        ])
        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/task")),
            runner: runner
        )

        _ = try await client.perform(.deleteAnnotation(uuid, deleted))

        let imported = try #require(runner.invocations[1].standardInput)
        let records = try JSONDecoder().decode([[String: JSONValue]].self, from: imported)
        guard case let .array(annotationValues) = records.first?["annotations"] else {
            Issue.record("Deletion import did not contain annotations")
            return
        }
        let annotations = annotationValues.compactMap(TaskAnnotation.init(jsonValue:))
        #expect(annotations == [TaskAnnotation(entry: "20260805T130000Z", description: "Duplicate text")])
    }

    @Test func addsLiteralAnnotationThroughTheMutationInterface() async throws {
        let uuid = UUID()
        let before = """
            [{"uuid":"\(uuid.uuidString)","description":"Write report","status":"pending"}]
            """
        let after = """
            [{"uuid":"\(uuid.uuidString)","description":"Write report","status":"pending","annotations":[{"entry":"20260805T120000Z","description":"Check https://example.com +literal"}]}]
            """
        let runner = RecordingRunner(results: [
            ProcessResult(exitCode: 0, standardOutput: before, standardError: ""),
            ProcessResult(exitCode: 0, standardOutput: "Annotated 1 task.", standardError: ""),
            ProcessResult(exitCode: 0, standardOutput: after, standardError: ""),
        ])
        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/task")),
            runner: runner
        )

        let receipt = try await client.perform(.annotate(uuid, "Check https://example.com +literal"))

        #expect(receipt.changes[uuid]?.before?.annotations.isEmpty == true)
        #expect(receipt.changes[uuid]?.after?.annotations.map(\.description) == [
            "Check https://example.com +literal"
        ])
        #expect(runner.invocations[1].arguments == [
            "rc.context=",
            "rc.confirmation=off",
            "rc.bulk=0",
            "rc.recurrence.confirmation=no",
            uuid.uuidString.lowercased(),
            "annotate",
            "--",
            "Check https://example.com +literal",
        ])
    }

    @Test func reopensACompletedTaskByRestoringPendingStatus() async throws {
        let uuid = UUID()
        let completed = """
            [{"uuid":"\(uuid.uuidString)","description":"Moved by mistake","status":"completed"}]
            """
        let pending = """
            [{"uuid":"\(uuid.uuidString)","description":"Moved by mistake","status":"pending"}]
            """
        let runner = RecordingRunner(results: [
            ProcessResult(exitCode: 0, standardOutput: completed, standardError: ""),
            ProcessResult(exitCode: 0, standardOutput: "Modified 1 task.", standardError: ""),
            ProcessResult(exitCode: 0, standardOutput: pending, standardError: ""),
        ])
        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/task")),
            runner: runner
        )

        _ = try await client.perform(.reopen(uuid))

        #expect(runner.invocations[1].arguments == [
            "rc.context=",
            "rc.confirmation=off",
            "rc.bulk=0",
            "rc.recurrence.confirmation=no",
            uuid.uuidString.lowercased(),
            "modify",
            "status:pending",
        ])
    }

    @Test func exposesAnnotationsChronologically() {
        let task = TaskRecord(fields: [
            "uuid": .string(UUID().uuidString),
            "annotations": .array([
                .object(["entry": .string("20260805T130000Z"), "description": .string("Second")]),
                .object(["entry": .string("20260805T120000Z"), "description": .string("First")]),
            ]),
        ])

        #expect(task.annotations.map(\.description) == ["First", "Second"])
        #expect(task.annotationCount == 2)
        #expect(task.isAnnotated)
    }

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
            matching: TaskQuery(view: .next, project: "TaskHelm", tag: "focus", rawFilter: "priority:H or due:today")
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
            "project:TaskHelm",
            "+focus",
            "priority:H",
            "or",
            "due:today",
            "export",
        ])
    }

    @Test func ignoresConfiguredReportLimitWhenExportingAllProjects() async throws {
        let runner = RecordingRunner(results: [
            ProcessResult(
                exitCode: 0,
                standardOutput: "status:pending -WAITING limit:page\n",
                standardError: ""
            ),
            ProcessResult(exitCode: 0, standardOutput: "[]", standardError: ""),
        ])
        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/task")),
            runner: runner
        )

        _ = try await client.tasks(matching: TaskQuery(view: .next))

        #expect(runner.invocations[1].arguments == [
            "rc.json.array=on",
            "status:pending",
            "-WAITING",
            "-PARENT",
            "export",
        ])
    }

    @Test func combinesMultipleSelectionsWithOrWithinEachFacet() async throws {
        let runner = RecordingRunner(results: [
            ProcessResult(exitCode: 0, standardOutput: "status:pending\n", standardError: ""),
            ProcessResult(exitCode: 0, standardOutput: "[]", standardError: ""),
        ])
        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/task")),
            runner: runner
        )

        _ = try await client.tasks(matching: TaskQuery(
            view: .next,
            projects: ["amber", "dsc"],
            tags: ["skill", "work"]
        ))

        #expect(runner.invocations[1].arguments == [
            "rc.json.array=on",
            "status:pending",
            "-PARENT",
            "(", "project:amber", "or", "project:dsc", ")",
            "(", "+skill", "or", "+work", ")",
            "export",
        ])
    }

    @Test func boardCombinesNextAndCompletedBeforeApplyingFacets() async throws {
        let runner = RecordingRunner(results: [
            ProcessResult(
                exitCode: 0,
                standardOutput: "status:pending -WAITING limit:page\n",
                standardError: ""
            ),
            ProcessResult(exitCode: 0, standardOutput: "[]", standardError: ""),
        ])
        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/task")),
            runner: runner
        )

        _ = try await client.tasks(
            matching: TaskQuery(view: .board, project: "dsc", tag: "skill", rawFilter: "priority:H")
        )

        #expect(runner.invocations[1].arguments == [
            "rc.json.array=on",
            "(", "status:pending", "-WAITING", "or", "status:completed", ")",
            "-PARENT",
            "project:dsc",
            "+skill",
            "priority:H",
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
        var standardInput: Data?
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
        invocations.append(Invocation(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            standardInput: nil
        ))
        return results.removeFirst()
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        standardInput: Data
    ) throws -> ProcessResult {
        lock.lock()
        defer { lock.unlock() }
        invocations.append(Invocation(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            standardInput: standardInput
        ))
        return results.removeFirst()
    }
}

private extension TaskAnnotation {
    init?(jsonValue: JSONValue) {
        guard case let .object(fields) = jsonValue,
              case let .string(entry) = fields["entry"],
              case let .string(description) = fields["description"] else { return nil }
        self.init(entry: entry, description: description)
    }
}
