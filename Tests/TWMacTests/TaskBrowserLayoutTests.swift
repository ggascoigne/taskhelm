import AppKit
import SwiftUI
import Testing
import TWMacCore
@testable import TWMac

@MainActor
@Suite("Task Browser layout")
struct TaskBrowserLayoutTests {
    @Test(arguments: BrowserDetailsPosition.allCases)
    func detailsSplitFillsTheBrowserHeight(position: BrowserDetailsPosition) async throws {
        let defaults = UserDefaults(suiteName: "TaskBrowserLayoutTests-\(UUID().uuidString)")!
        let model = TaskBrowserViewModel(
            client: LayoutBrowserClient(tasks: [layoutTask()]),
            defaults: defaults
        )
        model.setDetailsPosition(position)
        await model.refresh()
        let hostingView = NSHostingView(rootView: TaskBrowserView(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        let table = try #require(hostingView.descendants.compactMap { $0 as? NSTableView }.first)
        let tableHeight = try #require(table.enclosingScrollView).frame.height

        #expect(tableHeight >= (position == .right ? 600 : 250))
    }

    @Test func bottomDividerDoesNotMoveWhenSelectionIsCleared() async throws {
        let defaults = UserDefaults(suiteName: "TaskBrowserLayoutTests-\(UUID().uuidString)")!
        let task = layoutTask()
        let model = TaskBrowserViewModel(client: LayoutBrowserClient(tasks: [task]), defaults: defaults)
        model.setDetailsPosition(.bottom)
        await model.refresh()
        model.selection = [task.uuid]

        let hostingView = NSHostingView(rootView: TaskBrowserView(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        let selectedTable = try #require(hostingView.descendants.compactMap { $0 as? NSTableView }.first)
        let selectedListHeight = try #require(selectedTable.enclosingScrollView).frame.height

        model.selection.removeAll()
        await Task.yield()
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        let emptyTable = try #require(hostingView.descendants.compactMap { $0 as? NSTableView }.first)
        let emptyListHeight = try #require(emptyTable.enclosingScrollView).frame.height

        #expect(abs(emptyListHeight - selectedListHeight) < 1)
    }

    @Test func taskEditorUsesDateSelectorForDueDate() async throws {
        let defaults = UserDefaults(suiteName: "TaskBrowserLayoutTests-\(UUID().uuidString)")!
        let task = layoutTask(due: "20260812T000000Z")
        let model = TaskBrowserViewModel(client: LayoutBrowserClient(tasks: [task]), defaults: defaults)
        await model.refresh()
        model.selection = [task.uuid]
        model.beginEditing()

        let hostingView = NSHostingView(rootView: TaskBrowserView(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        let dueField = try #require(
            hostingView.descendants.compactMap { $0 as? NSTextField }.first {
                $0.placeholderString == "Due"
            }
        )
        #expect(!dueField.frame.isEmpty)
        #expect(hostingView.descendants.compactMap { $0 as? NSDatePicker }.isEmpty)
        #expect(model.edits?.due == "20260812T000000Z")
    }

    @Test func browserTableDoesNotDisplayRawTaskwarriorDueDate() {
        let rawDue = "20260812T000000Z"
        #expect(browserDueDisplayValue(rawDue) != rawDue)
        #expect(browserDueDisplayValue("").isEmpty)
    }

    private func layoutTask(due: String? = nil) -> TaskRecord {
        var fields: [String: JSONValue] = [
            "uuid": .string(UUID().uuidString),
            "description": .string("Selected task"),
            "status": .string("pending"),
        ]
        if let due { fields["due"] = .string(due) }
        return TaskRecord(fields: fields)
    }
}

private extension NSView {
    var descendants: [NSView] {
        subviews + subviews.flatMap(\.descendants)
    }
}

private struct LayoutBrowserClient: TaskBrowsing {
    let configuredTasks: [TaskRecord]

    init(tasks: [TaskRecord] = []) {
        configuredTasks = tasks
    }

    func tasks(matching query: TaskQuery) async throws -> [TaskRecord] { configuredTasks }

    func metadata() async throws -> TaskwarriorMetadata {
        TaskwarriorMetadata(projects: [], tags: [], priorities: [], context: nil)
    }
}
