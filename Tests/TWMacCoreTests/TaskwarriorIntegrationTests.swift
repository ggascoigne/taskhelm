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
    }
}
