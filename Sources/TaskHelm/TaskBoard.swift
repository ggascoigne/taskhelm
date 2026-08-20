import Foundation
import TaskHelmCore

enum BrowserBoardColumn: String, CaseIterable, Identifiable {
    case backlog
    case todo
    case inProgress
    case done

    var id: Self { self }

    var title: String {
        switch self {
        case .backlog: "Backlog"
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .done: "Done"
        }
    }
}

indirect enum BoardTaskRule {
    case all([BoardTaskRule])
    case any([BoardTaskRule])
    case complete(Bool)
    case started(Bool)
    case hasPriority(Bool)
    case hasDueDate(Bool)

    func matches(_ task: TaskRecord) -> Bool {
        switch self {
        case let .all(rules): rules.allSatisfy { $0.matches(task) }
        case let .any(rules): rules.contains { $0.matches(task) }
        case let .complete(expected): (task.status == "completed") == expected
        case let .started(expected): task.isActive == expected
        case let .hasPriority(expected): !task.priority.isEmpty == expected
        case let .hasDueDate(expected): !task.due.isEmpty == expected
        }
    }
}

struct BrowserBoardColumnDefinition: Identifiable {
    let id: BrowserBoardColumn
    let title: String
    let taskRule: BoardTaskRule
}

enum BoardTransitionAction {
    case choosePriority
    case clearPlanning
    case start
    case stopIntoTodo
    case stopAndClearPlanning
    case complete
    case reopenIntoBacklog
    case reopenIntoTodo
    case reopenAndStart
}

struct BrowserBoardTransitionRule {
    let source: BrowserBoardColumn?
    let destination: BrowserBoardColumn
    let action: BoardTransitionAction
}

enum BrowserBoardDropPlan: Equatable {
    case choosePriority
    case mutations([TaskMutation])
}

struct BrowserBoardDefinition {
    let columns: [BrowserBoardColumnDefinition]
    let transitions: [BrowserBoardTransitionRule]

    func column(containing task: TaskRecord) -> BrowserBoardColumn? {
        columns.first { $0.taskRule.matches(task) }?.id
    }

    func dropPlan(
        for task: TaskRecord,
        into destination: BrowserBoardColumn,
        priority: String? = nil
    ) -> BrowserBoardDropPlan? {
        guard let source = column(containing: task), source != destination else { return nil }
        let transition = transitions.first {
            $0.source == source && $0.destination == destination
        } ?? transitions.first {
            $0.source == nil && $0.destination == destination
        }
        guard let transition else { return nil }

        switch transition.action {
        case .choosePriority:
            guard let priority, !priority.isEmpty else { return .choosePriority }
            return .mutations([.edit(task.uuid, edits(for: task, priority: priority))])
        case .clearPlanning:
            return .mutations([.edit(task.uuid, edits(for: task, due: "", priority: ""))])
        case .start:
            return .mutations([.start(task.uuid)])
        case .stopIntoTodo:
            if !task.priority.isEmpty || !task.due.isEmpty {
                return .mutations([.stop(task.uuid)])
            }
            guard let priority, !priority.isEmpty else { return .choosePriority }
            return .mutations([
                .edit(task.uuid, edits(for: task, priority: priority)),
                .stop(task.uuid),
            ])
        case .stopAndClearPlanning:
            return .mutations([
                .edit(task.uuid, edits(for: task, due: "", priority: "")),
                .stop(task.uuid),
            ])
        case .complete:
            return .mutations([.complete(task.uuid)])
        case .reopenIntoBacklog:
            var mutations: [TaskMutation] = [.reopen(task.uuid)]
            if !task.priority.isEmpty || !task.due.isEmpty {
                mutations.append(.edit(task.uuid, edits(for: task, due: "", priority: "")))
            }
            return .mutations(mutations)
        case .reopenIntoTodo:
            if !task.priority.isEmpty || !task.due.isEmpty {
                return .mutations([.reopen(task.uuid)])
            }
            guard let priority, !priority.isEmpty else { return .choosePriority }
            return .mutations([
                .reopen(task.uuid),
                .edit(task.uuid, edits(for: task, priority: priority)),
            ])
        case .reopenAndStart:
            return .mutations([.reopen(task.uuid), .start(task.uuid)])
        }
    }

    private func edits(
        for task: TaskRecord,
        due: String? = nil,
        priority: String? = nil
    ) -> TaskEdits {
        TaskEdits(
            description: task.description,
            project: task.project,
            tags: task.tags,
            due: due ?? task.due,
            priority: priority ?? task.priority
        )
    }

    static let standard = BrowserBoardDefinition(
        columns: [
            BrowserBoardColumnDefinition(
                id: .backlog,
                title: "Backlog",
                taskRule: .all([
                    .complete(false), .started(false), .hasPriority(false), .hasDueDate(false),
                ])
            ),
            BrowserBoardColumnDefinition(
                id: .todo,
                title: "To Do",
                taskRule: .all([
                    .complete(false),
                    .started(false),
                    .any([.hasPriority(true), .hasDueDate(true)]),
                ])
            ),
            BrowserBoardColumnDefinition(
                id: .inProgress,
                title: "In Progress",
                taskRule: .all([.complete(false), .started(true)])
            ),
            BrowserBoardColumnDefinition(
                id: .done,
                title: "Done",
                taskRule: .complete(true)
            ),
        ],
        transitions: [
            BrowserBoardTransitionRule(source: .backlog, destination: .todo, action: .choosePriority),
            BrowserBoardTransitionRule(source: .todo, destination: .backlog, action: .clearPlanning),
            BrowserBoardTransitionRule(source: .backlog, destination: .inProgress, action: .start),
            BrowserBoardTransitionRule(source: .todo, destination: .inProgress, action: .start),
            BrowserBoardTransitionRule(source: .inProgress, destination: .todo, action: .stopIntoTodo),
            BrowserBoardTransitionRule(
                source: .inProgress,
                destination: .backlog,
                action: .stopAndClearPlanning
            ),
            BrowserBoardTransitionRule(
                source: .done,
                destination: .backlog,
                action: .reopenIntoBacklog
            ),
            BrowserBoardTransitionRule(
                source: .done,
                destination: .todo,
                action: .reopenIntoTodo
            ),
            BrowserBoardTransitionRule(
                source: .done,
                destination: .inProgress,
                action: .reopenAndStart
            ),
            BrowserBoardTransitionRule(source: nil, destination: .done, action: .complete),
        ]
    )
}
