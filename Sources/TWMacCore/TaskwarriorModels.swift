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

public enum TaskwarriorError: LocalizedError, Equatable {
    case executableNotFound(String)
    case unsupportedVersion(found: String, minimum: String)
    case processFailed(exitCode: Int32, message: String)
    case invalidCreationOutput(String)

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
        }
    }
}
