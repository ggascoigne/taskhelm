import Foundation
import TaskHelmCore

enum BrowserSortField: String, CaseIterable {
    case urgency
    case description
    case project
    case tags
    case due
    case priority

    var title: String { rawValue.capitalized }
}

enum BrowserDetailsPosition: String, CaseIterable {
    case right
    case bottom
}

@MainActor
final class TaskBrowserViewModel: ObservableObject {
    @Published private(set) var tasks: [TaskRecord] = []
    @Published private(set) var projects: [String] = []
    @Published private(set) var activeProjects: [String] = []
    @Published private(set) var completedProjects: [String] = []
    @Published private(set) var projectColors: [String: ProjectColor]
    @Published private(set) var tags: [String] = []
    @Published var selection: Set<UUID> = []
    @Published var view: BrowserViewKind = .next
    @Published private(set) var selectedProjects: Set<String> = []
    @Published private(set) var selectedTags: Set<String> = []
    @Published var rawFilter = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var sortField: BrowserSortField
    @Published private(set) var sortAscending: Bool
    @Published private(set) var detailsPosition: BrowserDetailsPosition
    @Published private(set) var rightDetailsWidth: Double
    @Published private(set) var bottomDetailsHeight: Double
    @Published var edits: TaskEdits?
    @Published var bulkEdits: BulkTaskEdits?
    @Published private(set) var isMutating = false
    @Published private(set) var undoReceipt: TaskMutationReceipt?

    private enum DefaultsKey {
        static let view = "browserView"
        static let sortField = "browserSortField"
        static let sortAscending = "browserSortAscending"
        static let detailsPosition = "browserDetailsPosition"
        static let rightDetailsWidth = "browserRightDetailsWidth"
        static let bottomDetailsHeight = "browserBottomDetailsHeight"
        static let projectColors = "browserProjectColors"
        static let userSelectedProjectColors = "browserUserSelectedProjectColors"
    }

    private let loadTasks: @MainActor (TaskQuery) async throws -> [TaskRecord]
    private let loadMetadata: @MainActor () async throws -> TaskwarriorMetadata
    private let performMutation: @MainActor (TaskMutation) async throws -> TaskMutationReceipt
    private let undoMutation: @MainActor (TaskMutationReceipt) async throws -> Void
    private let defaults: UserDefaults
    private var userSelectedProjectColors: Set<String>
    private var filterTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var priorityValues = ["H", "M", "L", ""]
    private var hasLoadedMetadata = false
    private let boardDefinition = BrowserBoardDefinition.standard

    init(client: any TaskBrowsing, defaults: UserDefaults = .standard) {
        loadTasks = { query in try await client.tasks(matching: query) }
        loadMetadata = { try await client.metadata() }
        performMutation = { _ in throw TaskwarriorError.processFailed(exitCode: -1, message: "Mutations unavailable.") }
        undoMutation = { _ in throw TaskwarriorError.processFailed(exitCode: -1, message: "Undo unavailable.") }
        self.defaults = defaults
        projectColors = Self.loadProjectColors(from: defaults)
        userSelectedProjectColors = Self.loadUserSelectedProjectColors(from: defaults)
        view = defaults.string(forKey: DefaultsKey.view).flatMap(BrowserViewKind.init(rawValue:)) ?? .next
        sortField = defaults.string(forKey: DefaultsKey.sortField).flatMap(BrowserSortField.init(rawValue:)) ?? .urgency
        sortAscending = defaults.object(forKey: DefaultsKey.sortAscending) as? Bool ?? false
        detailsPosition = defaults.string(forKey: DefaultsKey.detailsPosition)
            .flatMap(BrowserDetailsPosition.init(rawValue:)) ?? .right
        rightDetailsWidth = defaults.object(forKey: DefaultsKey.rightDetailsWidth) as? Double ?? 320
        bottomDetailsHeight = defaults.object(forKey: DefaultsKey.bottomDetailsHeight) as? Double ?? 300
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
        projectColors = Self.loadProjectColors(from: defaults)
        userSelectedProjectColors = Self.loadUserSelectedProjectColors(from: defaults)
        view = defaults.string(forKey: DefaultsKey.view).flatMap(BrowserViewKind.init(rawValue:)) ?? .next
        sortField = defaults.string(forKey: DefaultsKey.sortField).flatMap(BrowserSortField.init(rawValue:)) ?? .urgency
        sortAscending = defaults.object(forKey: DefaultsKey.sortAscending) as? Bool ?? false
        detailsPosition = defaults.string(forKey: DefaultsKey.detailsPosition)
            .flatMap(BrowserDetailsPosition.init(rawValue:)) ?? .right
        rightDetailsWidth = defaults.object(forKey: DefaultsKey.rightDetailsWidth) as? Double ?? 320
        bottomDetailsHeight = defaults.object(forKey: DefaultsKey.bottomDetailsHeight) as? Double ?? 300
    }

    var displayedTasks: [TaskRecord] {
        tasks.sorted(by: compare)
    }

    var tableSortOrder: [KeyPathComparator<TaskRecord>] {
        [sortField.comparator(ascending: sortAscending)]
    }

    func tasks(in column: BrowserBoardColumn) -> [TaskRecord] {
        displayedTasks.filter { boardDefinition.column(containing: $0) == column }
    }

    var boardColumns: [BrowserBoardColumnDefinition] { boardDefinition.columns }

    func projectColor(for project: String) -> ProjectColor? {
        projectColors[project]
    }

    func setProjectColor(_ color: ProjectColor, for project: String) {
        guard !project.isEmpty else { return }
        projectColors[project] = color
        userSelectedProjectColors.insert(project)
        persistProjectColors()
    }

    func selectBoardTask(_ uuid: UUID) {
        selection = [uuid]
    }

    func canDropBoardTask(_ uuid: UUID, into column: BrowserBoardColumn) -> Bool {
        guard let task = tasks.first(where: { $0.uuid == uuid }) else { return false }
        return boardDefinition.dropPlan(for: task, into: column) != nil
    }

    func boardDropNeedsPriority(_ uuid: UUID, into column: BrowserBoardColumn) -> Bool {
        guard let task = tasks.first(where: { $0.uuid == uuid }) else { return false }
        return boardDefinition.dropPlan(for: task, into: column) == .choosePriority
    }

    @discardableResult
    func moveBoardTask(
        _ uuid: UUID,
        into column: BrowserBoardColumn,
        priority: String? = nil
    ) async -> Bool {
        guard let task = tasks.first(where: { $0.uuid == uuid }),
              case let .mutations(mutations)? = boardDefinition.dropPlan(
                  for: task,
                  into: column,
                  priority: priority
              ) else { return false }
        selection = [uuid]
        return await mutate(mutations)
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

    func addNote(_ text: String) async -> Bool {
        guard let task = selectedTask else { return false }
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return false }
        return await mutate(.annotate(task.uuid, note))
    }

    func replaceNote(_ annotation: TaskAnnotation, with text: String) async -> Bool {
        guard let task = selectedTask, task.annotations.contains(annotation) else { return false }
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return false }
        return await mutate(.replaceAnnotation(task.uuid, annotation, note))
    }

    func deleteNote(_ annotation: TaskAnnotation) async -> Bool {
        guard let task = selectedTask, task.annotations.contains(annotation) else { return false }
        return await mutate(.deleteAnnotation(task.uuid, annotation))
    }

    func undo() async {
        guard let receipt = undoReceipt, !isMutating else { return }
        isMutating = true
        errorMessage = nil
        do {
            try await undoMutation(receipt)
            undoReceipt = nil
            hasLoadedMetadata = false
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
        isMutating = false
    }

    func selectView(_ value: BrowserViewKind) async {
        view = value
        defaults.set(value.rawValue, forKey: DefaultsKey.view)
        selection.removeAll()
        await refresh()
    }

    func toggleProject(_ value: String) async {
        if selectedProjects.contains(value) {
            selectedProjects.remove(value)
        } else {
            selectedProjects.insert(value)
        }
        selection.removeAll()
        await refresh()
    }

    func toggleTag(_ value: String) async {
        if selectedTags.contains(value) {
            selectedTags.remove(value)
        } else {
            selectedTags.insert(value)
        }
        selection.removeAll()
        await refresh()
    }

    func clearFacetSelections() async {
        selectedProjects.removeAll()
        selectedTags.removeAll()
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

    func setDetailsPosition(_ position: BrowserDetailsPosition) {
        detailsPosition = position
        defaults.set(position.rawValue, forKey: DefaultsKey.detailsPosition)
    }

    func setRightDetailsWidth(_ width: Double) {
        rightDetailsWidth = width
        defaults.set(width, forKey: DefaultsKey.rightDetailsWidth)
    }

    func setBottomDetailsHeight(_ height: Double) {
        bottomDetailsHeight = height
        defaults.set(height, forKey: DefaultsKey.bottomDetailsHeight)
    }

    func refresh(reloadMetadata: Bool = false) async {
        if reloadMetadata { hasLoadedMetadata = false }
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil

        do {
            async let taskResult = loadTasks(TaskQuery(
                view: view,
                projects: selectedProjects.sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                },
                tags: selectedTags.sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                },
                rawFilter: rawFilter
            ))
            let metadata = hasLoadedMetadata ? nil : try? await loadMetadata()
            let result = try await taskResult
            guard generation == loadGeneration else { return }
            tasks = result
            if let metadata {
                let active = Set(metadata.projects.filter { !$0.isEmpty })
                activeProjects = active.sorted(by: Self.caseInsensitiveAscending)
                completedProjects = Set(metadata.completedProjects.filter { !$0.isEmpty })
                    .subtracting(active)
                    .sorted(by: Self.caseInsensitiveAscending)
                projects = Array(active.union(completedProjects))
                tags = Array(Set(tags + Self.normalizedTags(metadata.tags)))
                if !metadata.priorities.isEmpty {
                    priorityValues = metadata.priorities
                }
                hasLoadedMetadata = true
            }
            let visibleActiveProjects = result
                .filter { $0.status != "completed" }
                .map(\.project)
                .filter { !$0.isEmpty }
            let visibleCompletedProjects = result
                .filter { $0.status == "completed" }
                .map(\.project)
                .filter { !$0.isEmpty }
            activeProjects = Array(Set(activeProjects + visibleActiveProjects))
                .sorted(by: Self.caseInsensitiveAscending)
            completedProjects = Array(Set(completedProjects + visibleCompletedProjects))
                .filter { !activeProjects.contains($0) }
                .sorted(by: Self.caseInsensitiveAscending)
            projects = Array(Set(projects + activeProjects + completedProjects))
                .sorted(by: Self.caseInsensitiveAscending)
            ensureProjectColors()
            tags = Array(Set(tags + Self.normalizedTags(result.flatMap(\.tags))))
                .sorted(by: Self.caseInsensitiveAscending)
            selection = selection.intersection(Set(result.map(\.id)))
            lastRefreshed = Date()
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
    }

    private static func normalizedTags(_ values: [String]) -> [String] {
        values
            .flatMap { value in
                value.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            .filter { !$0.isEmpty }
    }

    private static func caseInsensitiveAscending(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }

    private func ensureProjectColors() {
        let knownProjects = Set(projectColors.keys).union(projects)
        let selectedProjects = knownProjects
            .filter { userSelectedProjectColors.contains($0) }
            .sorted(by: Self.caseInsensitiveAscending)
        var acceptedColors = selectedProjects.compactMap { projectColors[$0] }
        var changed = false

        for project in knownProjects
            .subtracting(selectedProjects)
            .sorted(by: Self.caseInsensitiveAscending) {
            if let color = projectColors[project], color.isVisuallyDistinct(from: acceptedColors) {
                acceptedColors.append(color)
                continue
            }

            let color = ProjectColor.mostDistinct(from: acceptedColors)
            if projectColors[project] != color {
                projectColors[project] = color
                changed = true
            }
            acceptedColors.append(color)
        }
        if changed { persistProjectColors() }
    }

    private func persistProjectColors() {
        guard let data = try? JSONEncoder().encode(projectColors) else { return }
        defaults.set(data, forKey: DefaultsKey.projectColors)
        defaults.set(
            userSelectedProjectColors.sorted(by: Self.caseInsensitiveAscending),
            forKey: DefaultsKey.userSelectedProjectColors
        )
    }

    private static func loadProjectColors(from defaults: UserDefaults) -> [String: ProjectColor] {
        guard let data = defaults.data(forKey: DefaultsKey.projectColors),
              let colors = try? JSONDecoder().decode([String: ProjectColor].self, from: data) else {
            return [:]
        }
        return colors
    }

    private static func loadUserSelectedProjectColors(from defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: DefaultsKey.userSelectedProjectColors) ?? [])
    }

    @discardableResult
    private func mutate(_ mutation: TaskMutation) async -> Bool {
        await mutate([mutation])
    }

    @discardableResult
    private func mutate(_ mutations: [TaskMutation]) async -> Bool {
        guard !mutations.isEmpty else { return false }
        guard !isMutating else { return false }
        isMutating = true
        errorMessage = nil
        var receipts: [TaskMutationReceipt] = []
        do {
            for mutation in mutations {
                receipts.append(try await performMutation(mutation))
            }
            undoReceipt = Self.combinedReceipt(receipts)
            hasLoadedMetadata = false
            await refresh()
        } catch {
            let mutationError = error.localizedDescription
            if !receipts.isEmpty {
                undoReceipt = Self.combinedReceipt(receipts)
                hasLoadedMetadata = false
                await refresh()
            }
            errorMessage = mutationError
        }
        isMutating = false
        return errorMessage == nil
    }

    private static func combinedReceipt(_ receipts: [TaskMutationReceipt]) -> TaskMutationReceipt? {
        guard !receipts.isEmpty else { return nil }
        var changes: [UUID: TaskChange] = [:]
        for receipt in receipts {
            for (uuid, change) in receipt.changes {
                if let existing = changes[uuid] {
                    changes[uuid] = TaskChange(before: existing.before, after: change.after)
                } else {
                    changes[uuid] = change
                }
            }
        }
        return TaskMutationReceipt(
            changes: changes,
            feedback: receipts.map(\.feedback).filter { !$0.isEmpty }.joined(separator: "\n")
        )
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
