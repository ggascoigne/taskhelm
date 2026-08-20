import AppKit
import SwiftUI
import Testing
import TaskHelmCore
import UniformTypeIdentifiers
@testable import TaskHelm

@MainActor
@Suite("Task Browser layout")
struct TaskBrowserLayoutTests {
    @Test func boardDoesNotOverflowWhenAllMinimumWidthColumnsFit() {
        let availableWidth: CGFloat = 900

        #expect(
            BrowserBoardLayout.contentWidth(availableWidth: availableWidth, columnCount: 4)
                <= availableWidth
        )
    }

    @Test func configuresExistingBrowserWindowToMoveToTheActiveDesktop() {
        let behavior = TaskBrowserWindowPlacement.activeDesktopBehavior(
            from: [.managed, .canJoinAllSpaces]
        )

        #expect(behavior.contains(.managed))
        #expect(behavior.contains(.moveToActiveSpace))
        #expect(!behavior.contains(.canJoinAllSpaces))
    }

    @Test func findsBrowserWindowByStableIdentityAfterNavigationTitleChanges() {
        #expect(TaskBrowserWindowPlacement.isBrowserWindow(identifier: .taskBrowserWindow))
        #expect(!TaskBrowserWindowPlacement.isBrowserWindow(identifier: nil))
    }

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

    @Test func clickingBlankSpaceInBoardCardSelectsIt() async throws {
        var selected = false
        let hostingView = NSHostingView(
            rootView: BoardTaskCard(task: layoutTask(), isSelected: false) {
                selected = true
            }
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 260, height: 100)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        let blankPoint = NSPoint(x: hostingView.bounds.maxX - 6, y: hostingView.bounds.midY)
        let windowPoint = hostingView.convert(blankPoint, to: nil)
        let mouseDown = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let mouseUp = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0.01,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        ))

        window.sendEvent(mouseDown)
        window.sendEvent(mouseUp)
        await Task.yield()

        #expect(selected)
    }

    @Test func boardDragPayloadUsesAConcreteTextTypeAndRoundTripsTheTaskID() {
        let taskID = UUID()
        let value = BoardDragPayload.string(for: taskID)
        let provider = NSItemProvider(object: value as NSString)

        #expect(provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier))
        #expect(BoardDragPayload.taskID(from: value) == taskID)
        #expect(BoardDragPayload.taskID(from: taskID.uuidString) == nil)
    }

    @Test func projectColorWellIsCircularAndUsesItsNativeAnchoredPicker() throws {
        var color = Color.red
        let hostingView = NSHostingView(
            rootView: ProjectColorWell(
                color: Binding(get: { color }, set: { color = $0 }),
                label: "Project color"
            )
            .frame(width: 13, height: 13)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 13, height: 13)
        hostingView.layoutSubtreeIfNeeded()

        let well = try #require(hostingView.descendants.compactMap { $0 as? NSColorWell }.first)
        #expect(abs(well.frame.width - well.frame.height) < 0.5)
        #expect(well.colorWellStyle == .minimal)
        #expect(well.pulldownAction == nil)
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
