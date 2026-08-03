import SwiftUI

struct TaskBrowserCommandActions {
    var canEdit: Bool
    var canStart: Bool
    var canStop: Bool
    var canComplete: Bool
    var canDelete: Bool
    var canUndo: Bool
    var editTitle: String
    var edit: () -> Void
    var start: () -> Void
    var stop: () -> Void
    var complete: () -> Void
    var delete: () -> Void
    var undo: () -> Void
    var refresh: () -> Void
}

private struct TaskBrowserCommandsKey: FocusedValueKey {
    typealias Value = TaskBrowserCommandActions
}

extension FocusedValues {
    var taskBrowserCommands: TaskBrowserCommandActions? {
        get { self[TaskBrowserCommandsKey.self] }
        set { self[TaskBrowserCommandsKey.self] = newValue }
    }
}

struct TaskBrowserMenuCommands: Commands {
    @FocusedValue(\.taskBrowserCommands) private var actions

    var body: some Commands {
        CommandMenu("Task") {
            Button(actions?.editTitle ?? "Edit Task", action: { actions?.edit() })
                .keyboardShortcut("e", modifiers: .command)
                .disabled(actions?.canEdit != true)

            Button("Start", action: { actions?.start() })
                .disabled(actions?.canStart != true)

            Button("Stop", action: { actions?.stop() })
                .disabled(actions?.canStop != true)

            Button("Complete", action: { actions?.complete() })
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(actions?.canComplete != true)

            Divider()

            Button("Delete", role: .destructive, action: { actions?.delete() })
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(actions?.canDelete != true)

            Button("Undo Browser Action", action: { actions?.undo() })
                .keyboardShortcut("z", modifiers: .command)
                .disabled(actions?.canUndo != true)

            Divider()

            Button("Refresh Tasks", action: { actions?.refresh() })
                .keyboardShortcut("r", modifiers: .command)
                .disabled(actions == nil)
        }
    }
}
