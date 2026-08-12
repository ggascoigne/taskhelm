import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var displayValue: String {
        switch self {
        case let .string(value): value
        case let .number(value): value.formatted(.number.precision(.fractionLength(0...2)))
        case let .bool(value): value ? "Yes" : "No"
        case let .array(values): values.map(\.displayValue).joined(separator: ", ")
        case let .object(value):
            value.keys.sorted().map { "\($0): \(value[$0]?.displayValue ?? "")" }.joined(separator: ", ")
        case .null: "—"
        }
    }
}

public struct TaskAnnotation: Equatable, Identifiable, Sendable {
    public let entry: String
    public let description: String

    public init(entry: String, description: String) {
        self.entry = entry
        self.description = description
    }

    public var id: String { entry }
}

public struct TaskRecord: Codable, Equatable, Identifiable, Sendable {
    public let fields: [String: JSONValue]

    public init(fields: [String: JSONValue]) {
        self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        fields = try [String: JSONValue](from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try fields.encode(to: encoder)
    }

    public var id: UUID { uuid }
    public var uuid: UUID { UUID(uuidString: string("uuid")) ?? Self.invalidUUID }
    public var taskID: Int { Int(number("id")) }
    public var description: String { string("description") }
    public var project: String { string("project") }
    public var tags: [String] { strings("tags") }
    public var tagsText: String { tags.joined(separator: ", ") }
    public var due: String { string("due") }
    public var priority: String { string("priority") }
    public var urgency: Double { number("urgency") }
    public var status: String { string("status") }
    public var isActive: Bool { fields["start"] != nil && fields["end"] == nil }
    public var isRecurring: Bool { fields["recur"] != nil || status == "recurring" }
    public var annotations: [TaskAnnotation] {
        guard case let .array(values) = fields["annotations"] else { return [] }
        return values.compactMap { value in
            guard case let .object(fields) = value,
                  case let .string(entry) = fields["entry"],
                  case let .string(description) = fields["description"] else { return nil }
            return TaskAnnotation(entry: entry, description: description)
        }
        .sorted { $0.entry < $1.entry }
    }
    public var annotationCount: Int { annotations.count }
    public var isAnnotated: Bool { !annotations.isEmpty }
    public var isBlocked: Bool {
        guard case let .array(values) = fields["depends"] else { return false }
        return !values.isEmpty
    }

    public var sortedFields: [(key: String, value: JSONValue)] {
        fields.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    public var storedFields: [String: JSONValue] {
        fields.filter { $0.key != "id" && $0.key != "urgency" }
    }

    private func string(_ key: String) -> String {
        guard case let .string(value) = fields[key] else { return "" }
        return value
    }

    private func number(_ key: String) -> Double {
        switch fields[key] {
        case let .number(value): value
        case let .string(value): Double(value) ?? 0
        default: 0
        }
    }

    private func strings(_ key: String) -> [String] {
        guard case let .array(values) = fields[key] else { return [] }
        return values.compactMap {
            guard case let .string(value) = $0 else { return nil }
            return value
        }
    }

    private static let invalidUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}

public enum BrowserViewKind: String, CaseIterable, Codable, Sendable {
    case next
    case waiting
    case completed

    public var title: String { rawValue.capitalized }
}

public struct TaskQuery: Equatable, Sendable {
    public var view: BrowserViewKind
    public var project: String?
    public var tag: String?
    public var rawFilter: String

    public init(view: BrowserViewKind = .next, project: String? = nil, tag: String? = nil, rawFilter: String = "") {
        self.view = view
        self.project = project
        self.tag = tag
        self.rawFilter = rawFilter
    }
}
