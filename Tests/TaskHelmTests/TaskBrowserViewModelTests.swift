import Foundation
import Testing
import TaskHelmCore
@testable import TaskHelm

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
        let client = BrowserClient(results: [[], [], [], [], []])
        let model = TaskBrowserViewModel(client: client, defaults: ephemeralDefaults())

        await model.selectView(.completed)
        await model.toggleProject("TaskHelm")
        await model.toggleProject("Personal")
        await model.toggleTag("focus")
        await model.toggleTag("skill")

        #expect(client.queries.last == TaskQuery(
            view: .completed,
            projects: ["Personal", "TaskHelm"],
            tags: ["focus", "skill"]
        ))
    }

    @Test func allFacetSelectionClearsProjectsAndTags() async {
        let client = BrowserClient(results: [[], [], [], []])
        let model = TaskBrowserViewModel(client: client, defaults: ephemeralDefaults())

        await model.toggleTag("skill")
        await model.toggleProject("dsc")
        await model.clearFacetSelections()
        #expect(client.queries.last == TaskQuery(view: .next))
        #expect(model.selectedProjects.isEmpty)
        #expect(model.selectedTags.isEmpty)
    }

    @Test func selectingAnExistingFacetAgainDeselectsIt() async {
        let client = BrowserClient(results: [[], []])
        let model = TaskBrowserViewModel(client: client, defaults: ephemeralDefaults())

        await model.toggleTag("skill")
        await model.toggleTag("skill")
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

    @Test func remembersLastSelectedView() async {
        let defaults = ephemeralDefaults()
        let model = TaskBrowserViewModel(client: BrowserClient(results: [[]]), defaults: defaults)

        #expect(model.view == .next)

        await model.selectView(.board)
        let restored = TaskBrowserViewModel(client: BrowserClient(results: []), defaults: defaults)

        #expect(restored.view == .board)
    }

    @Test func assignsAndPersistsProjectColors() async {
        let defaults = ephemeralDefaults()
        let model = TaskBrowserViewModel(
            client: BrowserClient(
                results: [
                    [task(description: "First", project: "alpha")],
                    [task(description: "Second", project: "new-project")],
                ],
                projects: ["configured"]
            ),
            defaults: defaults
        )

        await model.refresh()
        #expect(model.projectColor(for: "alpha") != nil)
        #expect(model.projectColor(for: "configured") != nil)

        let chosen = ProjectColor(red: 0.15, green: 0.35, blue: 0.75)
        model.setProjectColor(chosen, for: "alpha")
        await model.refresh()

        #expect(model.projectColor(for: "new-project") != nil)

        let restored = TaskBrowserViewModel(client: BrowserClient(results: []), defaults: defaults)
        #expect(restored.projectColor(for: "alpha") == chosen)
        #expect(restored.projectColor(for: "configured") == model.projectColor(for: "configured"))
        #expect(restored.projectColor(for: "new-project") == model.projectColor(for: "new-project"))
    }

    @Test func repairsLegacyColorCollisionsAndPersistsDistinctAssignments() async throws {
        let defaults = ephemeralDefaults()
        let projects = (1...10).map { "project-\($0)" }
        let red = ProjectColor(red: 0.78, green: 0.20, blue: 0.18)
        let blue = ProjectColor(red: 0.18, green: 0.32, blue: 0.78)
        let legacyColors = Dictionary(uniqueKeysWithValues: projects.enumerated().map { index, project in
            (project, index < 3 ? red : blue)
        })
        defaults.set(try JSONEncoder().encode(legacyColors), forKey: "browserProjectColors")

        let model = TaskBrowserViewModel(
            client: BrowserClient(results: [[]], projects: projects),
            defaults: defaults
        )
        await model.refresh()

        let colors = try projects.map { project in
            try #require(model.projectColor(for: project))
        }
        let minimumDistance = colors.indices.dropLast().flatMap { leftIndex in
            colors.indices.dropFirst(leftIndex + 1).map { rightIndex in
                colors[leftIndex].distance(to: colors[rightIndex])
            }
        }.min()
        #expect(try #require(minimumDistance) >= 0.25)

        let restored = TaskBrowserViewModel(client: BrowserClient(results: []), defaults: defaults)
        for project in projects {
            #expect(restored.projectColor(for: project) == model.projectColor(for: project))
        }
    }

    @Test func partitionsMatchingTasksIntoBoardColumns() async {
        let backlog = task(description: "Backlog")
        let prioritized = task(description: "Prioritized", priority: "M")
        let scheduled = task(description: "Scheduled", due: "20260820T000000Z")
        let active = task(description: "Active", isActive: true)
        let completed = task(description: "Completed", status: "completed")
        let model = TaskBrowserViewModel(
            client: BrowserClient(results: [[backlog, prioritized, scheduled, active, completed]]),
            defaults: ephemeralDefaults()
        )
        await model.refresh()

        #expect(model.tasks(in: .backlog).map(\.description) == ["Backlog"])
        #expect(Set(model.tasks(in: .todo).map(\.description)) == ["Prioritized", "Scheduled"])
        #expect(model.tasks(in: .inProgress).map(\.description) == ["Active"])
        #expect(model.tasks(in: .done).map(\.description) == ["Completed"])
    }

    @Test func standardBoardDefinesDropRulesIndependentlyOfTheView() {
        let board = BrowserBoardDefinition.standard
        let backlog = task(description: "Backlog")
        let todo = task(description: "Todo", priority: "M", due: "20260820T000000Z")
        let active = task(description: "Active", priority: "M", isActive: true)
        let unplannedActive = task(description: "Unplanned active", isActive: true)
        let completed = task(description: "Completed", status: "completed")

        #expect(board.columns.map(\.id) == [.backlog, .todo, .inProgress, .done])
        #expect(board.dropPlan(for: backlog, into: .todo) == .choosePriority)
        #expect(board.dropPlan(for: backlog, into: .todo, priority: "L") == .mutations([
            .edit(
                backlog.uuid,
                TaskEdits(description: "Backlog", project: "", tags: [], due: "", priority: "L")
            ),
        ]))
        #expect(board.dropPlan(for: todo, into: .backlog) == .mutations([
            .edit(
                todo.uuid,
                TaskEdits(description: "Todo", project: "", tags: [], due: "", priority: "")
            ),
        ]))
        #expect(board.dropPlan(for: backlog, into: .inProgress) == .mutations([.start(backlog.uuid)]))
        #expect(board.dropPlan(for: active, into: .todo) == .mutations([.stop(active.uuid)]))
        #expect(board.dropPlan(for: unplannedActive, into: .todo) == .choosePriority)
        #expect(board.dropPlan(for: todo, into: .done) == .mutations([.complete(todo.uuid)]))
        #expect(board.dropPlan(for: completed, into: .backlog) == .mutations([.reopen(completed.uuid)]))
        #expect(board.dropPlan(for: completed, into: .todo) == .choosePriority)
        #expect(board.dropPlan(for: completed, into: .todo, priority: "L") == .mutations([
            .reopen(completed.uuid),
            .edit(
                completed.uuid,
                TaskEdits(description: "Completed", project: "", tags: [], due: "", priority: "L")
            ),
        ]))
        #expect(board.dropPlan(for: completed, into: .inProgress) == .mutations([
            .reopen(completed.uuid),
            .start(completed.uuid),
        ]))
    }

    @Test func boardMoveExecutesCompositeTransitionAsOneUndoableChange() async {
        let active = task(description: "Active", priority: "H", due: "20260820T000000Z", isActive: true)
        var mutations: [TaskMutation] = []
        let before = TaskChange(before: active, after: active)
        let model = TaskBrowserViewModel(
            defaults: ephemeralDefaults(),
            loadTasks: { _ in [active] },
            loadMetadata: {
                TaskwarriorMetadata(projects: [], tags: [], priorities: ["H", "M", "L"], context: nil)
            },
            performMutation: { mutation in
                mutations.append(mutation)
                return TaskMutationReceipt(changes: [active.uuid: before], feedback: "changed")
            },
            undoMutation: { _ in }
        )
        await model.refresh()

        let moved = await model.moveBoardTask(active.uuid, into: .backlog)

        #expect(moved)
        #expect(mutations == [
            .edit(
                active.uuid,
                TaskEdits(description: "Active", project: "", tags: [], due: "", priority: "")
            ),
            .stop(active.uuid),
        ])
        #expect(model.canUndo)
    }

    @Test func partialBoardMoveRemainsUndoableAndReportsTheFailure() async {
        let active = task(description: "Active", priority: "H", isActive: true)
        var mutationCount = 0
        let model = TaskBrowserViewModel(
            defaults: ephemeralDefaults(),
            loadTasks: { _ in [active] },
            loadMetadata: {
                TaskwarriorMetadata(projects: [], tags: [], priorities: ["H", "M", "L"], context: nil)
            },
            performMutation: { _ in
                mutationCount += 1
                if mutationCount == 2 {
                    throw TaskwarriorError.processFailed(exitCode: 1, message: "Could not stop task")
                }
                return TaskMutationReceipt(
                    changes: [active.uuid: TaskChange(before: active, after: active)],
                    feedback: "changed"
                )
            },
            undoMutation: { _ in }
        )
        await model.refresh()

        let moved = await model.moveBoardTask(active.uuid, into: .backlog)

        #expect(!moved)
        #expect(model.canUndo)
        #expect(model.errorMessage?.contains("Could not stop task") == true)
    }

    @Test func boardSelectionUpdatesImmediately() async {
        let selected = task(description: "Selected")
        let model = TaskBrowserViewModel(
            client: BrowserClient(results: [[selected]]),
            defaults: ephemeralDefaults()
        )
        await model.refresh()

        let start = ContinuousClock.now
        model.selectBoardTask(selected.uuid)

        #expect(model.selection == [selected.uuid])
        #expect(ContinuousClock.now - start < .milliseconds(10))
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

    @Test func splitsCombinedMetadataTagsIntoIndividualFacets() async {
        let model = TaskBrowserViewModel(
            client: BrowserClient(results: [[]], tags: ["skill,work"]),
            defaults: ephemeralDefaults()
        )

        await model.refresh()

        #expect(model.tags == ["skill", "work"])
        #expect(!model.tags.contains("skill,work"))
    }

    @Test func separatesCompletedOnlyProjectsFromActiveProjects() async {
        let model = TaskBrowserViewModel(
            client: BrowserClient(
                results: [[]],
                projects: ["Current", "Mixed"],
                completedProjects: ["Archived", "Mixed"]
            ),
            defaults: ephemeralDefaults()
        )

        await model.refresh()

        #expect(model.activeProjects == ["Current", "Mixed"])
        #expect(model.completedProjects == ["Archived"])
        #expect(model.projects == ["Archived", "Current", "Mixed"])
    }

    @Test func taskCreationRefreshReloadsProjectMetadata() async {
        var metadataLoadCount = 0
        let model = TaskBrowserViewModel(
            defaults: ephemeralDefaults(),
            loadTasks: { _ in [] },
            loadMetadata: {
                metadataLoadCount += 1
                return TaskwarriorMetadata(
                    projects: metadataLoadCount == 1 ? ["Existing"] : ["Existing", "New Project"],
                    tags: [],
                    priorities: [],
                    context: nil
                )
            },
            performMutation: { _ in TaskMutationReceipt(changes: [:], feedback: "") },
            undoMutation: { _ in }
        )

        await model.refresh()
        await model.refresh()
        #expect(metadataLoadCount == 1)
        #expect(model.activeProjects == ["Existing"])

        await model.refresh(reloadMetadata: true)
        #expect(metadataLoadCount == 2)
        #expect(model.activeProjects == ["Existing", "New Project"])
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
        due: String = "",
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
        if !due.isEmpty { fields["due"] = .string(due) }
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
    private let configuredCompletedProjects: [String]
    private let configuredTags: [String]
    private(set) var queries: [TaskQuery] = []

    init(
        results: [[TaskRecord]],
        priorityValues: [String] = ["H", "M", "L", ""],
        projects: [String] = [],
        completedProjects: [String] = [],
        tags: [String] = []
    ) {
        self.results = results
        configuredPriorityValues = priorityValues
        configuredProjects = projects
        configuredCompletedProjects = completedProjects
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
            context: nil,
            completedProjects: configuredCompletedProjects
        )
    }
}
