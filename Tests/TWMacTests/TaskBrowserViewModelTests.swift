import Foundation
import Testing
import TWMacCore
@testable import TWMac

@MainActor
@Suite("Task Browser model")
struct TaskBrowserViewModelTests {
    @Test func defaultsToUrgencyDescendingAndBuildsFacets() async {
        let low = task(description: "Low", project: "Personal", tags: ["later"], urgency: 1)
        let high = task(description: "High", project: "Work", tags: ["focus"], urgency: 12)
        let model = TaskBrowserViewModel(client: BrowserClient(results: [[low, high]]), defaults: ephemeralDefaults())

        await model.refresh()

        #expect(model.displayedTasks.map(\.description) == ["High", "Low"])
        #expect(model.projects == ["Personal", "Work"])
        #expect(model.tags == ["focus", "later"])
    }

    @Test func sendsSelectedViewAndFacetsToTaskwarrior() async {
        let client = BrowserClient(results: [[], [], []])
        let model = TaskBrowserViewModel(client: client, defaults: ephemeralDefaults())

        await model.selectView(.completed)
        await model.selectProject("TWMac")
        await model.selectTag("focus")

        #expect(client.queries.last == TaskQuery(view: .completed, project: "TWMac", tag: "focus"))
    }

    @Test func allProjectAndTagSelectionsClearTheOtherFacet() async {
        let client = BrowserClient(results: [[], [], [], []])
        let model = TaskBrowserViewModel(client: client, defaults: ephemeralDefaults())

        await model.selectTag("skill")
        await model.selectProject(nil)
        #expect(client.queries.last == TaskQuery(view: .next))

        await model.selectProject("dsc")
        await model.selectTag(nil)
        #expect(client.queries.last == TaskQuery(view: .next))
    }

    @Test func remembersClientLocalSorting() async {
        let defaults = ephemeralDefaults()
        let model = TaskBrowserViewModel(client: BrowserClient(results: []), defaults: defaults)

        model.updateSortOrder([KeyPathComparator(\TaskRecord.description, order: .forward)])
        let restored = TaskBrowserViewModel(client: BrowserClient(results: []), defaults: defaults)

        #expect(restored.sortField == .description)
        #expect(restored.sortAscending)
        #expect(restored.tableSortOrder.first?.keyPath == \TaskRecord.description)
        #expect(restored.tableSortOrder.first?.order == .forward)
    }

    @Test func remembersDetailsPosition() {
        let defaults = ephemeralDefaults()
        let model = TaskBrowserViewModel(client: BrowserClient(results: []), defaults: defaults)

        #expect(model.detailsPosition == .right)

        model.setDetailsPosition(.bottom)
        let restored = TaskBrowserViewModel(client: BrowserClient(results: []), defaults: defaults)

        #expect(restored.detailsPosition == .bottom)
    }

    @Test func remembersDetailsPaneSizes() {
        let defaults = ephemeralDefaults()
        let model = TaskBrowserViewModel(client: BrowserClient(results: []), defaults: defaults)

        model.setRightDetailsWidth(375)
        model.setBottomDetailsHeight(340)
        let restored = TaskBrowserViewModel(client: BrowserClient(results: []), defaults: defaults)

        #expect(restored.rightDetailsWidth == 375)
        #expect(restored.bottomDetailsHeight == 340)
    }

    @Test func placesUnsetPriorityBelowLowWhenSortingHighestFirst() async {
        let model = TaskBrowserViewModel(
            client: BrowserClient(results: [[
                task(description: "Unset", priority: ""),
                task(description: "Low", priority: "L"),
                task(description: "High", priority: "H"),
                task(description: "Medium", priority: "M"),
            ]]),
            defaults: ephemeralDefaults()
        )
        await model.refresh()

        model.updateSortOrder([KeyPathComparator(\TaskRecord.priority, order: .reverse)])

        #expect(model.displayedTasks.map(\.priority) == ["H", "M", "L", ""])
    }

    @Test func honorsTaskwarriorConfiguredPriorityOrder() async {
        let model = TaskBrowserViewModel(
            client: BrowserClient(
                results: [[
                    task(description: "Unset", priority: ""),
                    task(description: "Low", priority: "L"),
                    task(description: "High", priority: "H"),
                    task(description: "Medium", priority: "M"),
                ]],
                priorityValues: ["H", "M", "", "L"]
            ),
            defaults: ephemeralDefaults()
        )
        await model.refresh()

        model.updateSortOrder([KeyPathComparator(\TaskRecord.priority, order: .reverse)])

        #expect(model.displayedTasks.map(\.priority) == ["H", "M", "", "L"])
    }

    @Test func loadsEditSuggestionsFromTaskwarriorMetadata() async {
        let model = TaskBrowserViewModel(
            client: BrowserClient(
                results: [[task(description: "Visible", project: "Current", tags: ["now"])]],
                priorityValues: ["A", "B", ""],
                projects: ["Existing", "Current"],
                tags: ["later", "now"]
            ),
            defaults: ephemeralDefaults()
        )

        await model.refresh()

        #expect(model.projects == ["Current", "Existing"])
        #expect(model.tags == ["later", "now"])
        #expect(model.configuredPriorities == ["A", "B", ""])
    }

    @Test func sendsMultiSelectionActionsAsSingleMutations() async {
        let first = task(description: "First")
        let second = task(description: "Second", isActive: true)
        var mutations: [TaskMutation] = []
        let model = TaskBrowserViewModel(
            defaults: ephemeralDefaults(),
            loadTasks: { _ in [first, second] },
            loadMetadata: {
                TaskwarriorMetadata(projects: [], tags: [], priorities: ["H", "M", "L", ""], context: nil)
            },
            performMutation: { mutation in
                mutations.append(mutation)
                throw TaskwarriorError.processFailed(exitCode: -1, message: "Recorded")
            },
            undoMutation: { _ in }
        )
        await model.refresh()
        model.selection = [first.uuid, second.uuid]

        await model.startSelected()
        await model.stopSelected()
        await model.completeSelected()
        await model.deleteSelected()

        #expect(mutations == [
            .start(first.uuid),
            .stop(second.uuid),
            .completeMany([first.uuid, second.uuid]),
            .deleteMany([first.uuid, second.uuid]),
        ])
    }

    @Test func addsTrimmedNoteToTheSelectedTask() async {
        let selected = task(description: "Selected")
        var mutations: [TaskMutation] = []
        let model = TaskBrowserViewModel(
            defaults: ephemeralDefaults(),
            loadTasks: { _ in [selected] },
            loadMetadata: {
                TaskwarriorMetadata(projects: [], tags: [], priorities: [], context: nil)
            },
            performMutation: { mutation in
                mutations.append(mutation)
                return TaskMutationReceipt(changes: [:], feedback: "")
            },
            undoMutation: { _ in }
        )
        await model.refresh()
        model.selection = [selected.uuid]

        let added = await model.addNote("  A useful note\nwith detail.  ")

        #expect(added)
        #expect(mutations == [.annotate(selected.uuid, "A useful note\nwith detail.")])
        #expect(model.canUndo)
    }

    @Test func refusesEmptyNoteOrMissingSelection() async {
        let selected = task(description: "Selected")
        var mutations: [TaskMutation] = []
        let model = TaskBrowserViewModel(
            defaults: ephemeralDefaults(),
            loadTasks: { _ in [selected] },
            loadMetadata: {
                TaskwarriorMetadata(projects: [], tags: [], priorities: [], context: nil)
            },
            performMutation: { mutation in
                mutations.append(mutation)
                return TaskMutationReceipt(changes: [:], feedback: "")
            },
            undoMutation: { _ in }
        )
        await model.refresh()

        #expect(!(await model.addNote("   \n  ")))
        model.selection = [selected.uuid]
        #expect(!(await model.addNote("   \n  ")))
        #expect(mutations.isEmpty)
    }

    @Test func replacesAndDeletesNoteOnTheSelectedTask() async {
        let note = TaskAnnotation(entry: "20260805T120000Z", description: "Original")
        let selected = task(description: "Selected", annotations: [note])
        var mutations: [TaskMutation] = []
        let model = TaskBrowserViewModel(
            defaults: ephemeralDefaults(),
            loadTasks: { _ in [selected] },
            loadMetadata: {
                TaskwarriorMetadata(projects: [], tags: [], priorities: [], context: nil)
            },
            performMutation: { mutation in
                mutations.append(mutation)
                return TaskMutationReceipt(changes: [:], feedback: "")
            },
            undoMutation: { _ in }
        )
        await model.refresh()
        model.selection = [selected.uuid]

        #expect(await model.replaceNote(note, with: "  Revised  "))
        #expect(await model.deleteNote(note))

        #expect(mutations == [
            .replaceAnnotation(selected.uuid, note, "Revised"),
            .deleteAnnotation(selected.uuid, note),
        ])
    }

    @Test func bulkEditingProducesOneUndoableMutation() async {
        let first = task(description: "First", project: "Old", tags: ["remove"])
        let second = task(description: "Second")
        var mutations: [TaskMutation] = []
        let model = TaskBrowserViewModel(
            defaults: ephemeralDefaults(),
            loadTasks: { _ in [first, second] },
            loadMetadata: {
                TaskwarriorMetadata(projects: ["New"], tags: ["add", "remove"], priorities: [], context: nil)
            },
            performMutation: { mutation in
                mutations.append(mutation)
                return TaskMutationReceipt(changes: [:], feedback: "")
            },
            undoMutation: { _ in }
        )
        await model.refresh()
        model.selection = [first.uuid, second.uuid]

        model.beginEditing()
        model.bulkEdits = BulkTaskEdits(project: "New", tagsToAdd: ["add"], tagsToRemove: ["remove"])
        await model.saveEditing()

        #expect(mutations == [
            .bulkEdit(
                [first.uuid, second.uuid],
                BulkTaskEdits(project: "New", tagsToAdd: ["add"], tagsToRemove: ["remove"])
            )
        ])
        #expect(!model.isEditing)
        #expect(model.canUndo)
    }

    @Test func selectionDrivenCommandsTrackTaskApplicability() async {
        let pending = task(description: "Pending")
        let active = task(description: "Active", isActive: true)
        let completed = task(description: "Completed", status: "completed")
        let model = TaskBrowserViewModel(
            client: BrowserClient(results: [[pending, active, completed]]),
            defaults: ephemeralDefaults()
        )
        await model.refresh()

        #expect(!model.selectionCanComplete)
        #expect(!model.selectionCanStart)
        #expect(!model.selectionCanStop)

        model.selection = [pending.uuid]
        #expect(model.selectionCanComplete)
        #expect(model.selectionCanStart)
        #expect(!model.selectionCanStop)

        model.selection = [active.uuid]
        #expect(model.selectionCanComplete)
        #expect(!model.selectionCanStart)
        #expect(model.selectionCanStop)

        model.selection = [pending.uuid, active.uuid]
        #expect(model.selectionCanStart)
        #expect(model.selectionCanStop)

        model.selection = [pending.uuid, active.uuid, completed.uuid]
        #expect(model.selectionCanComplete)
        #expect(model.selectionCanStart)
        #expect(model.selectionCanStop)

        model.selection = [completed.uuid]
        #expect(!model.selectionCanComplete)
        #expect(!model.selectionCanStart)
        #expect(!model.selectionCanStop)
    }

    private func task(
        description: String,
        project: String = "",
        tags: [String] = [],
        urgency: Double = 0,
        priority: String = "",
        status: String = "pending",
        isActive: Bool = false,
        annotations: [TaskAnnotation] = []
    ) -> TaskRecord {
        var fields: [String: JSONValue] = [
            "uuid": .string(UUID().uuidString),
            "description": .string(description),
            "project": .string(project),
            "tags": .array(tags.map(JSONValue.string)),
            "urgency": .number(urgency),
            "priority": .string(priority),
            "status": .string(status),
        ]
        if isActive { fields["start"] = .string("20260803T120000Z") }
        if !annotations.isEmpty {
            fields["annotations"] = .array(annotations.map { annotation in
                .object([
                    "entry": .string(annotation.entry),
                    "description": .string(annotation.description),
                ])
            })
        }
        return TaskRecord(fields: fields)
    }

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "TaskBrowserViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private final class BrowserClient: TaskBrowsing, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [[TaskRecord]]
    private let configuredPriorityValues: [String]
    private let configuredProjects: [String]
    private let configuredTags: [String]
    private(set) var queries: [TaskQuery] = []

    init(
        results: [[TaskRecord]],
        priorityValues: [String] = ["H", "M", "L", ""],
        projects: [String] = [],
        tags: [String] = []
    ) {
        self.results = results
        configuredPriorityValues = priorityValues
        configuredProjects = projects
        configuredTags = tags
    }

    func tasks(matching query: TaskQuery) async throws -> [TaskRecord] {
        lock.withLock {
            queries.append(query)
            return results.isEmpty ? [] : results.removeFirst()
        }
    }


    func priorityValues() async throws -> [String] { configuredPriorityValues }

    func metadata() async throws -> TaskwarriorMetadata {
        TaskwarriorMetadata(
            projects: configuredProjects,
            tags: configuredTags,
            priorities: configuredPriorityValues,
            context: nil
        )
    }
}
