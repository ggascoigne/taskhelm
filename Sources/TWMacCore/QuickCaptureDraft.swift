import Foundation

public struct QuickCaptureDraft: Equatable, Sendable {
    public var description: String
    public var project: String
    public var tags: [String]
    public var due: String
    public var priority: String

    public init(
        description: String = "",
        project: String = "",
        tags: [String] = [],
        due: String = "",
        priority: String = ""
    ) {
        self.description = description
        self.project = project
        self.tags = tags
        self.due = due
        self.priority = priority
    }

    public var isValid: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum SelectedTextNormalizer {
    public static func normalize(_ text: String) -> String {
        text
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
