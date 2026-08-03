import Foundation
import Testing
@testable import TWMacCore

@Suite("Taskwarrior integration")
struct TaskwarriorIntegrationTests {
    @Test func createsTaskWithoutParsingDescription() async throws {
        let taskURL = URL(fileURLWithPath: "/opt/homebrew/bin/task")
        guard FileManager.default.isExecutableFile(atPath: taskURL.path) else { return }

        let dataURL = FileManager.default.temporaryDirectory
            .appending(path: "tw-mac-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dataURL) }

        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(
                executableURL: taskURL,
                taskRCURL: URL(fileURLWithPath: "/dev/null"),
                taskDataURL: dataURL
            ),
            runner: FoundationProcessRunner()
        )

        let created = try await client.createTask(
            from: QuickCaptureDraft(description: "project:literal +not-a-tag", project: "actual", tags: ["real"])
        )

        #expect(created.uuid.uuidString.isEmpty == false)

        let exported = try FoundationProcessRunner().run(
            executableURL: taskURL,
            arguments: ["export"],
            environment: ["TASKRC": "/dev/null", "TASKDATA": dataURL.path]
        )
        #expect(exported.exitCode == 0)
        let tasks = try JSONSerialization.jsonObject(with: Data(exported.standardOutput.utf8)) as? [[String: Any]]

        #expect(tasks?.first?["description"] as? String == "project:literal +not-a-tag")
        #expect(tasks?.first?["project"] as? String == "actual")
        #expect(tasks?.first?["tags"] as? [String] == ["real"])

        let metadata = try await client.metadata()
        #expect(metadata.projects == ["actual"])
        #expect(metadata.tags == ["real"])
        #expect(metadata.priorities == ["H", "M", "L"])
        #expect(metadata.context == nil)

        let browserTasks = try await client.tasks(matching: TaskQuery(view: .next, project: "actual", tag: "real"))
        #expect(browserTasks.count == 1)
        #expect(browserTasks.first?.uuid == created.uuid)
        #expect(browserTasks.first?.description == "project:literal +not-a-tag")
    }

    @Test func mutatesAndRestoresOnlyTheOperationFootprint() async throws {
        let taskURL = URL(fileURLWithPath: "/opt/homebrew/bin/task")
        guard FileManager.default.isExecutableFile(atPath: taskURL.path) else { return }
        let dataURL = FileManager.default.temporaryDirectory
            .appending(path: "tw-mac-mutation-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dataURL) }
        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(
                executableURL: taskURL,
                taskRCURL: URL(fileURLWithPath: "/dev/null"),
                taskDataURL: dataURL
            ),
            runner: FoundationProcessRunner()
        )
        let created = try await client.createTask(from: QuickCaptureDraft(description: "Before", priority: "L"))

        let edit = try await client.perform(
            .edit(
                created.uuid,
                TaskEdits(description: "After", project: "TWMac", tags: ["focus"], due: "tomorrow", priority: "H")
            )
        )
        let uuidFilter = created.uuid.uuidString.lowercased()
        var tasks = try await client.tasks(matching: TaskQuery(rawFilter: uuidFilter))
        #expect(tasks.first?.description == "After")
        #expect(tasks.first?.project == "TWMac")
        #expect(tasks.first?.priority == "H")

        try await client.undo(edit)
        tasks = try await client.tasks(matching: TaskQuery(rawFilter: uuidFilter))
        #expect(tasks.first?.description == "Before")
        #expect(tasks.first?.project == "")
        #expect(tasks.first?.priority == "L")

        let completion = try await client.perform(.complete(created.uuid))
        #expect(try await client.tasks(matching: TaskQuery(view: .completed, rawFilter: uuidFilter)).count == 1)
        try await client.undo(completion)
        #expect(try await client.tasks(matching: TaskQuery(rawFilter: uuidFilter)).count == 1)

        let started = try await client.perform(.start(created.uuid))
        #expect(try await client.tasks(matching: TaskQuery(rawFilter: uuidFilter)).first?.isActive == true)
        try await client.undo(started)
        #expect(try await client.tasks(matching: TaskQuery(rawFilter: uuidFilter)).first?.isActive == false)

        let deletion = try await client.perform(.delete(created.uuid))
        #expect(try await client.tasks(matching: TaskQuery(rawFilter: uuidFilter)).isEmpty)
        try await client.undo(deletion)
        #expect(try await client.tasks(matching: TaskQuery(rawFilter: uuidFilter)).count == 1)

        let conflict = try await client.perform(
            .edit(
                created.uuid,
                TaskEdits(description: "Browser edit", project: "", tags: [], due: "", priority: "H")
            )
        )
        let external = try FoundationProcessRunner().run(
            executableURL: taskURL,
            arguments: ["rc.confirmation=off", uuidFilter, "modify", "priority:M"],
            environment: ["TASKRC": "/dev/null", "TASKDATA": dataURL.path]
        )
        #expect(external.exitCode == 0)
        await #expect(throws: TaskwarriorError.undoConflict) {
            try await client.undo(conflict)
        }
    }


    @Test func bulkMutationsAndUndoApplyToTheWholeSelection() async throws {
        let taskURL = URL(fileURLWithPath: "/opt/homebrew/bin/task")
        guard FileManager.default.isExecutableFile(atPath: taskURL.path) else { return }
        let dataURL = FileManager.default.temporaryDirectory
            .appending(path: "tw-mac-bulk-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dataURL) }
        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(
                executableURL: taskURL,
                taskRCURL: URL(fileURLWithPath: "/dev/null"),
                taskDataURL: dataURL
            ),
            runner: FoundationProcessRunner()
        )
        let first = try await client.createTask(from: QuickCaptureDraft(description: "First"))
        let second = try await client.createTask(from: QuickCaptureDraft(description: "Second"))
        let uuids = [first.uuid, second.uuid]

        let started = try await client.perform(.startMany(uuids))
        #expect(try await client.tasks(matching: TaskQuery()).allSatisfy { $0.isActive })
        try await client.undo(started)
        #expect(try await client.tasks(matching: TaskQuery()).allSatisfy { !$0.isActive })

        _ = try await client.perform(.startMany(uuids))
        let stopped = try await client.perform(.stopMany(uuids))
        #expect(try await client.tasks(matching: TaskQuery()).allSatisfy { !$0.isActive })
        try await client.undo(stopped)
        #expect(try await client.tasks(matching: TaskQuery()).allSatisfy { $0.isActive })

        let completed = try await client.perform(.completeMany(uuids))
        #expect(try await client.tasks(matching: TaskQuery(view: .completed)).count == 2)
        try await client.undo(completed)
        #expect(try await client.tasks(matching: TaskQuery()).count == 2)

        let deleted = try await client.perform(.deleteMany(uuids))
        #expect(try await client.tasks(matching: TaskQuery()).isEmpty)
        try await client.undo(deleted)
        #expect(try await client.tasks(matching: TaskQuery()).count == 2)
    }

    @Test func bulkEditingAndUndoApplyProjectAndTagChangesTogether() async throws {
        let taskURL = URL(fileURLWithPath: "/opt/homebrew/bin/task")
        guard FileManager.default.isExecutableFile(atPath: taskURL.path) else { return }
        let dataURL = FileManager.default.temporaryDirectory
            .appending(path: "tw-mac-bulk-edit-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dataURL) }
        let client = TaskwarriorClient(
            environment: TaskwarriorEnvironment(
                executableURL: taskURL,
                taskRCURL: URL(fileURLWithPath: "/dev/null"),
                taskDataURL: dataURL
            ),
            runner: FoundationProcessRunner()
        )
        let first = try await client.createTask(from: QuickCaptureDraft(description: "First", tags: ["remove"]))
        let second = try await client.createTask(from: QuickCaptureDraft(description: "Second"))
        let uuids = [first.uuid, second.uuid]

        let receipt = try await client.perform(
            .bulkEdit(
                uuids,
                BulkTaskEdits(project: "TWMac", tagsToAdd: ["focus"], tagsToRemove: ["remove"])
            )
        )
        var tasks = try await client.tasks(matching: TaskQuery())
        #expect(tasks.allSatisfy { $0.project == "TWMac" })
        #expect(tasks.allSatisfy { $0.tags.contains("focus") })
        #expect(tasks.allSatisfy { !$0.tags.contains("remove") })

        try await client.undo(receipt)

        tasks = try await client.tasks(matching: TaskQuery())
        #expect(tasks.allSatisfy { $0.project.isEmpty })
        #expect(tasks.first(where: { $0.uuid == first.uuid })?.tags == ["remove"])
        #expect(tasks.first(where: { $0.uuid == second.uuid })?.tags == [])
    }
}
