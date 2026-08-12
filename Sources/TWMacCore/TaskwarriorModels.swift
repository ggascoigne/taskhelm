import Foundation

public struct TaskwarriorEnvironment: Equatable, Sendable {
    public var executableURL: URL
    public var taskRCURL: URL?
    public var taskDataURL: URL?

    public init(executableURL: URL, taskRCURL: URL? = nil, taskDataURL: URL? = nil) {
        self.executableURL = executableURL
        self.taskRCURL = taskRCURL
        self.taskDataURL = taskDataURL
    }
}

public struct TaskwarriorInstallation: Equatable, Sendable {
    public var version: String

    public init(version: String) {
        self.version = version
    }
}

public struct TaskwarriorMetadata: Equatable, Sendable {
    public var projects: [String]
    public var tags: [String]
    public var priorities: [String]
    public var context: String?

    public init(projects: [String], tags: [String], priorities: [String], context: String?) {
        self.projects = projects
        self.tags = tags
        self.priorities = priorities
        self.context = context
    }
}

public struct CreatedTask: Equatable, Sendable {
    public var uuid: UUID
    public var feedback: String

    public init(uuid: UUID, feedback: String) {
        self.uuid = uuid
        self.feedback = feedback
    }
}

public struct TaskEdits: Equatable, Sendable {
    public var description: String
    public var project: String
    public var tags: [String]
    public var due: String
    public var priority: String

    public init(description: String, project: String, tags: [String], due: String, priority: String) {
        self.description = description
        self.project = project
        self.tags = tags
        self.due = due
        self.priority = priority
    }
}

public struct BulkTaskEdits: Equatable, Sendable {
    public var project: String?
    public var tagsToAdd: [String]
    public var tagsToRemove: [String]

    public init(project: String? = nil, tagsToAdd: [String] = [], tagsToRemove: [String] = []) {
        self.project = project
        self.tagsToAdd = tagsToAdd
        self.tagsToRemove = tagsToRemove
    }

    public var isEmpty: Bool {
        project == nil && tagsToAdd.isEmpty && tagsToRemove.isEmpty
    }
}

public enum TaskMutation: Equatable, Sendable {
    case edit(UUID, TaskEdits)
    case bulkEdit([UUID], BulkTaskEdits)
    case annotate(UUID, String)
    case replaceAnnotation(UUID, TaskAnnotation, String)
    case deleteAnnotation(UUID, TaskAnnotation)
    case complete(UUID)
    case completeMany([UUID])
    case start(UUID)
    case startMany([UUID])
    case stop(UUID)
    case stopMany([UUID])
    case delete(UUID)
    case deleteMany([UUID])
}

public struct TaskChange: Equatable, Sendable {
    public var before: TaskRecord?
    public var after: TaskRecord?
}

public struct TaskMutationReceipt: Equatable, Sendable {
    public var changes: [UUID: TaskChange]
    public var feedback: String

    public init(changes: [UUID: TaskChange], feedback: String) {
        self.changes = changes
        self.feedback = feedback
    }
}

public enum TaskwarriorError: LocalizedError, Equatable {
    case executableNotFound(String)
    case unsupportedVersion(found: String, minimum: String)
    case processFailed(exitCode: Int32, message: String)
    case invalidCreationOutput(String)
    case invalidExport(String)
    case invalidFilter(String)
    case taskNotFound(UUID)
    case annotationNotFound(UUID)
    case undoConflict
    case undoFailed

    public var errorDescription: String? {
        switch self {
        case let .executableNotFound(path):
            "Taskwarrior was not found at \(path). Choose the correct executable in Settings."
        case let .unsupportedVersion(found, minimum):
            "Taskwarrior \(minimum) or later is required; found \(found)."
        case let .processFailed(_, message):
            message
        case .invalidCreationOutput:
            "Taskwarrior created no recognizable task UUID."
        case let .invalidExport(message):
            "Taskwarrior returned invalid task data: \(message)"
        case let .invalidFilter(message):
            "Invalid filter: \(message)"
        case let .taskNotFound(uuid):
            "Task \(uuid) no longer exists."
        case .annotationNotFound:
            "The note no longer exists or changed in another Taskwarrior client."
        case .undoConflict:
            "Undo was refused because an affected task changed after this operation."
        case .undoFailed:
            "Taskwarrior could not restore the operation completely."
        }
    }
}
