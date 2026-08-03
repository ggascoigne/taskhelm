import Foundation
import TWMacCore

enum BrowserSortField: String, CaseIterable {
    case urgency
    case description
    case project
    case tags
    case due
    case priority

    var title: String { rawValue.capitalized }
}

@MainActor
final class TaskBrowserViewModel: ObservableObject {
    @Published private(set) var tasks: [TaskRecord] = []
    @Published private(set) var projects: [String] = []
    @Published private(set) var tags: [String] = []
    @Published var selection: Set<UUID> = []
    @Published var view: BrowserViewKind = .next
    @Published var project: String?
    @Published var tag: String?
    @Published var rawFilter = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var sortField: BrowserSortField
    @Published private(set) var sortAscending: Bool
    @Published var edits: TaskEdits?
    @Published var bulkEdits: BulkTaskEdits?
    @Published private(set) var isMutating = false
    @Published private(set) var undoReceipt: TaskMutationReceipt?

    private enum DefaultsKey {
        static let sortField = "browserSortField"
        static let sortAscending = "browserSortAscending"
    }

    private let loadTasks: @MainActor (TaskQuery) async throws -> [TaskRecord]
    private let loadMetadata: @MainActor () async throws -> TaskwarriorMetadata
    private let performMutation: @MainActor (TaskMutation) async throws -> TaskMutationReceipt
    private let undoMutation: @MainActor (TaskMutationReceipt) async throws -> Void
    private let defaults: UserDefaults
    private var filterTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var priorityValues = ["H", "M", "L", ""]
    private var hasLoadedMetadata = false

    init(client: any TaskBrowsing, defaults: UserDefaults = .standard) {
        loadTasks = { query in try await client.tasks(matching: query) }
        loadMetadata = { try await client.metadata() }
        performMutation = { _ in throw TaskwarriorError.processFailed(exitCode: -1, message: "Mutations unavailable.") }
        undoMutation = { _ in throw TaskwarriorError.processFailed(exitCode: -1, message: "Undo unavailable.") }
        self.defaults = defaults
        sortField = defaults.string(forKey: DefaultsKey.sortField).flatMap(BrowserSortField.init(rawValue:)) ?? .urgency
        sortAscending = defaults.object(forKey: DefaultsKey.sortAscending) as? Bool ?? false
    }

    init(
        defaults: UserDefaults = .standard,
        loadTasks: @escaping @MainActor (TaskQuery) async throws -> [TaskRecord],
        loadMetadata: @escaping @MainActor () async throws -> TaskwarriorMetadata,
        performMutation: @escaping @MainActor (TaskMutation) async throws -> TaskMutationReceipt,
        undoMutation: @escaping @MainActor (TaskMutationReceipt) async throws -> Void
    ) {
        self.loadTasks = loadTasks
        self.loadMetadata = loadMetadata
        self.performMutation = performMutation
        self.undoMutation = undoMutation
        self.defaults = defaults
        sortField = defaults.string(forKey: DefaultsKey.sortField).flatMap(BrowserSortField.init(rawValue:)) ?? .urgency
        sortAscending = defaults.object(forKey: DefaultsKey.sortAscending) as? Bool ?? false
    }

    var displayedTasks: [TaskRecord] {
        tasks.sorted(by: compare)
    }

    var tableSortOrder: [KeyPathComparator<TaskRecord>] {
        [sortField.comparator(ascending: sortAscending)]
    }

    var selectedTask: TaskRecord? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return tasks.first { $0.id == id }
    }

    var selectedTasks: [TaskRecord] {
        tasks.filter { selection.contains($0.id) }
    }

    var selectionCount: Int { selectedTasks.count }

    var selectionCanComplete: Bool {
        selectedTasks.contains { $0.status == "pending" || $0.status == "waiting" }
    }

    var selectionCanStart: Bool {
        selectedTasks.contains {
            ($0.status == "pending" || $0.status == "waiting") && !$0.isActive
        }
    }

    var selectionCanStop: Bool {
        selectedTasks.contains {
            ($0.status == "pending" || $0.status == "waiting") && $0.isActive
        }
    }

    var canUndo: Bool { undoReceipt != nil && !isMutating }
    var isEditing: Bool { edits != nil || bulkEdits != nil }
    var configuredPriorities: [String] { priorityValues }

    func beginEditing() {
        if let task = selectedTask {
            edits = TaskEdits(
                description: task.description,
                project: task.project,
                tags: task.tags,
                due: task.due,
                priority: task.priority
            )
        } else if selectionCount > 1 {
            bulkEdits = BulkTaskEdits()
        }
    }

    func cancelEditing() {
        edits = nil
        bulkEdits = nil
    }

    func saveEditing() async {
        if let task = selectedTask, let edits {
            await mutate(.edit(task.uuid, edits))
        } else if let bulkEdits, !bulkEdits.isEmpty {
            await mutate(.bulkEdit(selectedTasks.map(\.uuid), bulkEdits))
        } else {
            return
        }
        if errorMessage == nil { cancelEditing() }
    }

    func completeSelected() async {
        let uuids = selectedTasks
            .filter { $0.status == "pending" || $0.status == "waiting" }
            .map(\.uuid)
        guard !uuids.isEmpty else { return }
        await mutate(uuids.count == 1 ? .complete(uuids[0]) : .completeMany(uuids))
    }

    func deleteSelected() async {
        let uuids = selectedTasks.map(\.uuid)
        guard !uuids.isEmpty else { return }
        await mutate(uuids.count == 1 ? .delete(uuids[0]) : .deleteMany(uuids))
    }

    func startSelected() async {
        let uuids = selectedTasks
            .filter { ($0.status == "pending" || $0.status == "waiting") && !$0.isActive }
            .map(\.uuid)
        guard !uuids.isEmpty else { return }
        await mutate(uuids.count == 1 ? .start(uuids[0]) : .startMany(uuids))
    }

    func stopSelected() async {
        let uuids = selectedTasks
            .filter { ($0.status == "pending" || $0.status == "waiting") && $0.isActive }
            .map(\.uuid)
        guard !uuids.isEmpty else { return }
        await mutate(uuids.count == 1 ? .stop(uuids[0]) : .stopMany(uuids))
    }

    func undo() async {
        guard let receipt = undoReceipt, !isMutating else { return }
        isMutating = true
        errorMessage = nil
        do {
            try await undoMutation(receipt)
            undoReceipt = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
        isMutating = false
    }

    func selectView(_ value: BrowserViewKind) async {
        view = value
        selection.removeAll()
        await refresh()
    }

    func selectProject(_ value: String?) async {
        project = value
        selection.removeAll()
        await refresh()
    }

    func selectTag(_ value: String?) async {
        tag = value
        selection.removeAll()
        await refresh()
    }

    func updateRawFilter(_ value: String) {
        rawFilter = value
        filterTask?.cancel()
        filterTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func updateSortOrder(_ order: [KeyPathComparator<TaskRecord>]) {
        guard let comparator = order.first,
              let field = BrowserSortField(keyPath: comparator.keyPath) else { return }
        sortField = field
        sortAscending = comparator.order == .forward
        defaults.set(sortField.rawValue, forKey: DefaultsKey.sortField)
        defaults.set(sortAscending, forKey: DefaultsKey.sortAscending)
    }

    func refresh() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil

        do {
            async let taskResult = loadTasks(TaskQuery(view: view, project: project, tag: tag, rawFilter: rawFilter))
            let metadata = hasLoadedMetadata ? nil : try? await loadMetadata()
            let result = try await taskResult
            guard generation == loadGeneration else { return }
            tasks = result
            if let metadata {
                projects = Array(Set(projects + metadata.projects))
                tags = Array(Set(tags + metadata.tags))
                if !metadata.priorities.isEmpty {
                    priorityValues = metadata.priorities
                }
                hasLoadedMetadata = true
            }
            projects = Array(Set(projects + result.map(\.project).filter { !$0.isEmpty }))
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            tags = Array(Set(tags + result.flatMap(\.tags)))
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            selection = selection.intersection(Set(result.map(\.id)))
            lastRefreshed = Date()
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
    }

    private func mutate(_ mutation: TaskMutation) async {
        guard !isMutating else { return }
        isMutating = true
        errorMessage = nil
        do {
            undoReceipt = try await performMutation(mutation)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
        isMutating = false
    }

    private func compare(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
        let comparison: ComparisonResult = switch sortField {
        case .urgency: compare(lhs.urgency, rhs.urgency)
        case .description: lhs.description.localizedCaseInsensitiveCompare(rhs.description)
        case .project: lhs.project.localizedCaseInsensitiveCompare(rhs.project)
        case .tags: lhs.tagsText.localizedCaseInsensitiveCompare(rhs.tagsText)
        case .due: lhs.due.localizedCaseInsensitiveCompare(rhs.due)
        case .priority: comparePriority(lhs.priority, rhs.priority)
        }
        if comparison == .orderedSame {
            return lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
        }
        return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    private func compare(_ lhs: Double, _ rhs: Double) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private func comparePriority(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsRank = priorityValues.firstIndex(of: lhs) ?? priorityValues.count
        let rhsRank = priorityValues.firstIndex(of: rhs) ?? priorityValues.count
        if lhsRank < rhsRank { return .orderedDescending }
        if lhsRank > rhsRank { return .orderedAscending }
        return .orderedSame
    }
}

private extension BrowserSortField {
    init?(keyPath: AnyKeyPath) {
        switch keyPath {
        case \TaskRecord.urgency: self = .urgency
        case \TaskRecord.description: self = .description
        case \TaskRecord.project: self = .project
        case \TaskRecord.tagsText: self = .tags
        case \TaskRecord.due: self = .due
        case \TaskRecord.priority: self = .priority
        default: return nil
        }
    }

    func comparator(ascending: Bool) -> KeyPathComparator<TaskRecord> {
        let order: SortOrder = ascending ? .forward : .reverse
        return switch self {
        case .urgency: KeyPathComparator(\TaskRecord.urgency, order: order)
        case .description: KeyPathComparator(\TaskRecord.description, order: order)
        case .project: KeyPathComparator(\TaskRecord.project, order: order)
        case .tags: KeyPathComparator(\TaskRecord.tagsText, order: order)
        case .due: KeyPathComparator(\TaskRecord.due, order: order)
        case .priority: KeyPathComparator(\TaskRecord.priority, order: order)
        }
    }
}
