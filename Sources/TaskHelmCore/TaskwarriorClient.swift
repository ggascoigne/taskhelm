import Foundation

public protocol TaskwarriorServing {
    func validateInstallation() async throws -> TaskwarriorInstallation
    func createTask(from draft: QuickCaptureDraft) async throws -> CreatedTask
    func metadata() async throws -> TaskwarriorMetadata
}

public protocol TaskBrowsing: Sendable {
    func tasks(matching query: TaskQuery) async throws -> [TaskRecord]
    func priorityValues() async throws -> [String]
    func metadata() async throws -> TaskwarriorMetadata
}

public protocol TaskMutating: Sendable {
    func perform(_ mutation: TaskMutation) async throws -> TaskMutationReceipt
    func undo(_ receipt: TaskMutationReceipt) async throws
}

public extension TaskBrowsing {
    func priorityValues() async throws -> [String] { ["H", "M", "L", ""] }

    func metadata() async throws -> TaskwarriorMetadata {
        TaskwarriorMetadata(projects: [], tags: [], priorities: try await priorityValues(), context: nil)
    }
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

        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        var feedback = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            let annotation = try await run(arguments: [
                "rc.confirmation=off", uuid.uuidString.lowercased(), "annotate", "--", note,
            ])
            try requireSuccess(annotation)
            let annotationFeedback = annotation.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            feedback = [feedback, annotationFeedback].filter { !$0.isEmpty }.joined(separator: "\n")
        }

        return CreatedTask(uuid: uuid, feedback: feedback)
    }

    public func metadata() async throws -> TaskwarriorMetadata {
        async let projectsResult = run(arguments: ["+PENDING", "_unique", "project"])
        async let completedProjectsResult = run(arguments: ["status:completed", "_unique", "project"])
        async let tagsResult = run(arguments: ["+PENDING", "_unique", "tags"])
        async let prioritiesResult = run(arguments: ["_get", "rc.uda.priority.values"])
        async let contextResult = run(arguments: ["_get", "rc.context"])

        let projects = try await projectsResult
        let completedProjects = try await completedProjectsResult
        let tags = try await tagsResult
        let priorities = try await prioritiesResult
        let context = try await contextResult

        try requireSuccess(projects)
        try requireSuccess(completedProjects)
        try requireSuccess(tags)
        try requireSuccess(priorities)

        return TaskwarriorMetadata(
            projects: Self.lines(in: projects.standardOutput),
            tags: Self.lines(in: tags.standardOutput)
                .flatMap { $0.split(separator: ",") }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != $0.uppercased() },
            priorities: priorities.standardOutput
                .split(separator: ",", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            context: context.exitCode == 0 ? context.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil,
            completedProjects: Self.lines(in: completedProjects.standardOutput)
        )
    }

    public func priorityValues() async throws -> [String] {
        let result = try await run(arguments: ["_get", "rc.uda.priority.values"])
        try requireSuccess(result)
        var values = result.standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !values.contains("") { values.append("") }
        return values
    }

    public func tasks(matching query: TaskQuery) async throws -> [TaskRecord] {
        var filter: [String]
        switch query.view {
        case .next:
            let result = try await run(arguments: ["_get", "rc.report.next.filter"])
            try requireSuccess(result)
            filter = try Self.filterArguments(in: result.standardOutput).filter {
                !$0.lowercased().hasPrefix("limit:")
            }
        case .board:
            let result = try await run(arguments: ["_get", "rc.report.next.filter"])
            try requireSuccess(result)
            let nextFilter = try Self.filterArguments(in: result.standardOutput).filter {
                !$0.lowercased().hasPrefix("limit:")
            }
            filter = ["("] + nextFilter + ["or", "status:completed", ")"]
        case .waiting:
            filter = ["status:waiting"]
        case .completed:
            filter = ["status:completed"]
        }

        filter.append("-PARENT")
        filter.append(contentsOf: Self.anyFacet(query.projects) { "project:\($0)" })
        filter.append(contentsOf: Self.anyFacet(query.tags) { "+\($0)" })
        filter.append(contentsOf: try Self.filterArguments(in: query.rawFilter))

        let result = try await run(arguments: ["rc.json.array=on"] + filter + ["export"])
        try requireSuccess(result)
        do {
            return try JSONDecoder().decode([TaskRecord].self, from: Data(result.standardOutput.utf8))
        } catch {
            throw TaskwarriorError.invalidExport(error.localizedDescription)
        }
    }

    private static func anyFacet(_ values: [String], token: (String) -> String) -> [String] {
        let tokens = values.filter { !$0.isEmpty }.map(token)
        guard tokens.count > 1 else { return tokens }
        return ["("] + tokens.enumerated().flatMap { index, value in
            index == 0 ? [value] : ["or", value]
        } + [")"]
    }

    public func perform(_ mutation: TaskMutation) async throws -> TaskMutationReceipt {
        let before = try await allTasks()
        let result: ProcessResult
        switch mutation {
        case .replaceAnnotation, .deleteAnnotation:
            result = try await importAnnotationMutation(mutation, tasks: before)
        default:
            let arguments = try mutationArguments(mutation, tasks: before)
            result = try await run(arguments: arguments)
        }
        try requireSuccess(result)
        let after = try await allTasks()
        let changes = Self.changes(from: before, to: after)
        return TaskMutationReceipt(
            changes: changes,
            feedback: [result.standardOutput, result.standardError]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        )
    }

    public func undo(_ receipt: TaskMutationReceipt) async throws {
        let current = Dictionary(uniqueKeysWithValues: try await allTasks().map { ($0.uuid, $0) })
        for (uuid, change) in receipt.changes {
            guard Self.sameStoredState(current[uuid], change.after) else { throw TaskwarriorError.undoConflict }
        }

        let recordsToRestore = receipt.changes.values.compactMap { change -> [String: JSONValue]? in
            guard let before = change.before else { return nil }
            var fields = before.storedFields
            fields["modified"] = .string(Self.nextImportTimestamp())
            return fields
        }
        if !recordsToRestore.isEmpty {
            let data = try JSONEncoder().encode(recordsToRestore)
            let result = try await run(
                arguments: ["rc.context=", "rc.confirmation=off", "rc.recurrence.confirmation=no", "import", "-"],
                standardInput: data
            )
            try requireSuccess(result)
        }

        for (uuid, change) in receipt.changes where change.before == nil && change.after != nil {
            if current[uuid]?.status != "deleted" {
                try requireSuccess(try await run(arguments: mutationPrefix + [uuid.uuidString.lowercased(), "delete"]))
            }
            try requireSuccess(try await run(arguments: mutationPrefix + [uuid.uuidString.lowercased(), "purge"]))
        }

        let restored = Dictionary(uniqueKeysWithValues: try await allTasks().map { ($0.uuid, $0) })
        guard receipt.changes.allSatisfy({ Self.sameRestoredState(restored[$0.key], $0.value.before) }) else {
            throw TaskwarriorError.undoFailed
        }
    }

    private func run(arguments: [String], includeTaskEnvironment: Bool = true) async throws -> ProcessResult {
        let executableURL = environment.executableURL
        let processEnvironment = includeTaskEnvironment ? taskEnvironment : [:]
        let runner = runner

        return try await Task.detached(priority: .userInitiated) {
            try runner.run(executableURL: executableURL, arguments: arguments, environment: processEnvironment)
        }.value
    }

    private func run(arguments: [String], standardInput: Data) async throws -> ProcessResult {
        let executableURL = environment.executableURL
        let processEnvironment = taskEnvironment
        let runner = runner
        return try await Task.detached(priority: .userInitiated) {
            try runner.run(
                executableURL: executableURL,
                arguments: arguments,
                environment: processEnvironment,
                standardInput: standardInput
            )
        }.value
    }

    private var mutationPrefix: [String] {
        ["rc.context=", "rc.confirmation=off", "rc.bulk=0", "rc.recurrence.confirmation=no"]
    }

    private func allTasks() async throws -> [TaskRecord] {
        let result = try await run(arguments: ["rc.context=", "rc.json.array=on", "export"])
        try requireSuccess(result)
        do {
            return try JSONDecoder().decode([TaskRecord].self, from: Data(result.standardOutput.utf8))
        } catch {
            throw TaskwarriorError.invalidExport(error.localizedDescription)
        }
    }

    private func mutationArguments(_ mutation: TaskMutation, tasks: [TaskRecord]) throws -> [String] {
        let uuids: [UUID]
        let command: [String]
        switch mutation {
        case let .edit(value, edits):
            uuids = [value]
            guard let task = tasks.first(where: { $0.uuid == value }) else {
                throw TaskwarriorError.taskNotFound(value)
            }
            var modifications = ["project:\(edits.project)", "due:\(edits.due)", "priority:\(edits.priority)"]
            modifications += task.tags.filter { !edits.tags.contains($0) }.map { "-\($0)" }
            modifications += edits.tags.filter { !task.tags.contains($0) }.map { "+\($0)" }
            command = ["modify"] + modifications + ["--", edits.description]
        case let .bulkEdit(values, edits):
            uuids = values
            var modifications: [String] = []
            if let project = edits.project {
                modifications.append("project:\(project)")
            }
            modifications += edits.tagsToAdd.map { "+\($0)" }
            modifications += edits.tagsToRemove.map { "-\($0)" }
            guard !modifications.isEmpty else {
                throw TaskwarriorError.processFailed(exitCode: -1, message: "No bulk changes to apply.")
            }
            command = ["modify"] + modifications
        case let .annotate(value, text):
            uuids = [value]
            let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else {
                throw TaskwarriorError.processFailed(exitCode: -1, message: "A note cannot be empty.")
            }
            command = ["annotate", "--", note]
        case .replaceAnnotation, .deleteAnnotation:
            throw TaskwarriorError.processFailed(
                exitCode: -1,
                message: "Annotation replacement must use Taskwarrior import."
            )
        case let .complete(value): uuids = [value]; command = ["done"]
        case let .completeMany(values): uuids = values; command = ["done"]
        case let .reopen(value): uuids = [value]; command = ["modify", "status:pending"]
        case let .start(value): uuids = [value]; command = ["start"]
        case let .startMany(values): uuids = values; command = ["start"]
        case let .stop(value): uuids = [value]; command = ["stop"]
        case let .stopMany(values): uuids = values; command = ["stop"]
        case let .delete(value): uuids = [value]; command = ["delete"]
        case let .deleteMany(values): uuids = values; command = ["delete"]
        }
        guard !uuids.isEmpty else {
            throw TaskwarriorError.processFailed(exitCode: -1, message: "No tasks selected.")
        }
        for uuid in uuids where !tasks.contains(where: { $0.uuid == uuid }) {
            throw TaskwarriorError.taskNotFound(uuid)
        }
        let filters = uuids.map { $0.uuidString.lowercased() }.sorted()
        return mutationPrefix + filters + command
    }

    private func importAnnotationMutation(
        _ mutation: TaskMutation,
        tasks: [TaskRecord]
    ) async throws -> ProcessResult {
        let uuid: UUID
        let original: TaskAnnotation
        let replacement: String?
        switch mutation {
        case let .replaceAnnotation(value, annotation, text):
            uuid = value
            original = annotation
            let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else {
                throw TaskwarriorError.processFailed(exitCode: -1, message: "A note cannot be empty.")
            }
            replacement = note
        case let .deleteAnnotation(value, annotation):
            uuid = value
            original = annotation
            replacement = nil
        default:
            throw TaskwarriorError.processFailed(exitCode: -1, message: "Invalid annotation mutation.")
        }

        guard let task = tasks.first(where: { $0.uuid == uuid }) else {
            throw TaskwarriorError.taskNotFound(uuid)
        }
        var fields = task.storedFields
        guard case let .array(existingValues) = fields["annotations"] else {
            throw TaskwarriorError.annotationNotFound(uuid)
        }
        var values = existingValues
        guard let index = values.firstIndex(where: { Self.matches($0, annotation: original) }) else {
            throw TaskwarriorError.annotationNotFound(uuid)
        }
        values.remove(at: index)

        if let replacement {
            let usedEntries = Set(existingValues.compactMap(Self.annotationEntry))
            values.append(.object([
                "entry": .string(Self.nextAnnotationTimestamp(avoiding: usedEntries)),
                "description": .string(replacement),
            ]))
        }
        fields["annotations"] = .array(values)
        fields["modified"] = .string(Self.nextImportTimestamp())

        let data = try JSONEncoder().encode([fields])
        return try await run(
            arguments: ["rc.context=", "rc.confirmation=off", "rc.recurrence.confirmation=no", "import", "-"],
            standardInput: data
        )
    }

    private static func matches(_ value: JSONValue, annotation: TaskAnnotation) -> Bool {
        guard case let .object(fields) = value,
              case let .string(entry) = fields["entry"],
              case let .string(description) = fields["description"] else { return false }
        return entry == annotation.entry && description == annotation.description
    }

    private static func annotationEntry(_ value: JSONValue) -> String? {
        guard case let .object(fields) = value,
              case let .string(entry) = fields["entry"] else { return nil }
        return entry
    }

    private static func nextAnnotationTimestamp(avoiding usedEntries: Set<String>) -> String {
        var date = Date()
        var value = taskTimestamp(date)
        while usedEntries.contains(value) {
            date.addTimeInterval(1)
            value = taskTimestamp(date)
        }
        return value
    }

    private static func changes(from before: [TaskRecord], to after: [TaskRecord]) -> [UUID: TaskChange] {
        let beforeByID = Dictionary(uniqueKeysWithValues: before.map { ($0.uuid, $0) })
        let afterByID = Dictionary(uniqueKeysWithValues: after.map { ($0.uuid, $0) })
        return Set(beforeByID.keys).union(afterByID.keys).reduce(into: [:]) { result, uuid in
            let old = beforeByID[uuid]
            let new = afterByID[uuid]
            if !sameStoredState(old, new) { result[uuid] = TaskChange(before: old, after: new) }
        }
    }

    private static func sameStoredState(_ lhs: TaskRecord?, _ rhs: TaskRecord?) -> Bool {
        lhs?.storedFields == rhs?.storedFields
    }

    private static func sameRestoredState(_ lhs: TaskRecord?, _ rhs: TaskRecord?) -> Bool {
        lhs?.storedFields.filter { $0.key != "modified" } == rhs?.storedFields.filter { $0.key != "modified" }
    }

    private static func nextImportTimestamp() -> String {
        taskTimestamp(Date().addingTimeInterval(1))
    }

    private static func taskTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
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

    static func filterArguments(in text: String) throws -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false

        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            if isEscaping {
                current.append(character)
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty {
                    arguments.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        guard quote == nil else { throw TaskwarriorError.invalidFilter("unterminated quote") }
        if isEscaping { current.append("\\") }
        if !current.isEmpty { arguments.append(current) }
        return arguments
    }
}

extension TaskwarriorClient: TaskwarriorServing {}
extension TaskwarriorClient: TaskBrowsing {}
extension TaskwarriorClient: TaskMutating {}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
