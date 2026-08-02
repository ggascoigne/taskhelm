import Foundation

public protocol TaskwarriorServing {
    func validateInstallation() async throws -> TaskwarriorInstallation
    func createTask(from draft: QuickCaptureDraft) async throws -> CreatedTask
    func metadata() async throws -> TaskwarriorMetadata
}

public struct TaskwarriorClient<Runner: ProcessRunning>: Sendable {
    public static var minimumVersion: String { "3.4.0" }

    private let environment: TaskwarriorEnvironment
    private let runner: Runner

    public init(environment: TaskwarriorEnvironment, runner: Runner) {
        self.environment = environment
        self.runner = runner
    }

    public func validateInstallation() async throws -> TaskwarriorInstallation {
        let result = try await run(arguments: ["--version"], includeTaskEnvironment: false)
        try requireSuccess(result)

        let version = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.compareVersions(version, Self.minimumVersion) != .orderedAscending else {
            throw TaskwarriorError.unsupportedVersion(found: version, minimum: Self.minimumVersion)
        }

        return TaskwarriorInstallation(version: version)
    }

    public func createTask(from draft: QuickCaptureDraft) async throws -> CreatedTask {
        var arguments = ["rc.verbose=new-uuid", "rc.confirmation=off", "add"]

        if !draft.project.isEmpty {
            arguments.append("project:\(draft.project)")
        }
        arguments.append(contentsOf: draft.tags.filter { !$0.isEmpty }.map { "+\($0)" })
        if !draft.due.isEmpty {
            arguments.append("due:\(draft.due)")
        }
        if !draft.priority.isEmpty {
            arguments.append("priority:\(draft.priority)")
        }
        arguments.append("--")
        arguments.append(draft.description.trimmingCharacters(in: .whitespacesAndNewlines))

        let result = try await run(arguments: arguments)
        try requireSuccess(result)

        guard let uuid = Self.firstUUID(in: result.standardOutput) else {
            throw TaskwarriorError.invalidCreationOutput(result.standardOutput)
        }

        return CreatedTask(uuid: uuid, feedback: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func metadata() async throws -> TaskwarriorMetadata {
        async let projectsResult = run(arguments: ["+PENDING", "_unique", "project"])
        async let tagsResult = run(arguments: ["+PENDING", "_unique", "tags"])
        async let prioritiesResult = run(arguments: ["_get", "rc.uda.priority.values"])
        async let contextResult = run(arguments: ["_get", "rc.context"])

        let projects = try await projectsResult
        let tags = try await tagsResult
        let priorities = try await prioritiesResult
        let context = try await contextResult

        try requireSuccess(projects)
        try requireSuccess(tags)
        try requireSuccess(priorities)

        return TaskwarriorMetadata(
            projects: Self.lines(in: projects.standardOutput),
            tags: Self.lines(in: tags.standardOutput).filter { $0 != $0.uppercased() },
            priorities: priorities.standardOutput
                .split(separator: ",", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            context: context.exitCode == 0 ? context.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil
        )
    }

    private func run(arguments: [String], includeTaskEnvironment: Bool = true) async throws -> ProcessResult {
        let executableURL = environment.executableURL
        let processEnvironment = includeTaskEnvironment ? taskEnvironment : [:]
        let runner = runner

        return try await Task.detached(priority: .userInitiated) {
            try runner.run(executableURL: executableURL, arguments: arguments, environment: processEnvironment)
        }.value
    }

    private var taskEnvironment: [String: String] {
        var values: [String: String] = [:]
        if let taskRCURL = environment.taskRCURL {
            values["TASKRC"] = taskRCURL.path
        }
        if let taskDataURL = environment.taskDataURL {
            values["TASKDATA"] = taskDataURL.path
        }
        return values
    }

    private func requireSuccess(_ result: ProcessResult) throws {
        guard result.exitCode == 0 else {
            let message = [result.standardError, result.standardOutput]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "Taskwarrior exited with code \(result.exitCode)."
            throw TaskwarriorError.processFailed(exitCode: result.exitCode, message: message)
        }
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }

    static func firstUUID(in text: String) -> UUID? {
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return UUID(uuidString: String(text[range]))
    }

    static func lines(in text: String) -> [String] {
        text
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

extension TaskwarriorClient: TaskwarriorServing {}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
