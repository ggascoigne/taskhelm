import AppKit
import SwiftUI
import Testing
import TaskHelmCore
@testable import TaskHelm

@MainActor
@Suite("Quick Capture regressions", .serialized)
struct QuickCaptureRegressionTests {
    @Test func panelDoesNotReserveAnEmptyNativeTitlebar() {
        #expect(!QuickCapturePanelController.panelStyleMask.contains(.titled))
    }

    @Test func borderlessQuickCapturePanelCanReceiveKeyboardInput() {
        let panel = QuickCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 230),
            styleMask: QuickCapturePanelController.panelStyleMask,
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }

        #expect(panel.canBecomeKey)
    }

    @Test func borderlessPanelKeepsRoundedCorners() throws {
        let panel = QuickCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 230),
            styleMask: QuickCapturePanelController.panelStyleMask,
            backing: .buffered,
            defer: false
        )
        let hostedView = NSView(frame: panel.contentLayoutRect)

        QuickCapturePanelController.applyRoundedAppearance(to: panel, hostedView: hostedView)

        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
        #expect(try #require(hostedView.layer).cornerRadius == 12)
        #expect(hostedView.layer?.cornerCurve == .continuous)
        #expect(hostedView.layer?.masksToBounds == true)
    }

    @Test func successfulCreationAnnouncesThatBrowserDataChanged() async {
        let client = RecordingTaskwarriorClient()
        let notification = Notification.Name("TaskHelmTaskCreated")
        var receivedCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: notification,
            object: nil,
            queue: nil
        ) { _ in
            receivedCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let model = QuickCaptureViewModel(client: client, onCancel: {}, onCreated: {})
        model.prepare(description: "New project task")
        model.draft.project = "new-project"

        await model.submit()

        #expect(receivedCount == 1)
    }

    @Test func commandBRequestsTaskBrowser() throws {
        _ = NSApplication.shared
        let panel = QuickCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }
        var requestCount = 0
        panel.onShowTaskBrowser = { requestCount += 1 }

        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: "b",
                charactersIgnoringModifiers: "b",
                isARepeat: false,
                keyCode: 11
            )
        )
        let handled = panel.performKeyEquivalent(with: event)

        #expect(handled)
        #expect(requestCount == 1)
    }

    @Test func returnSubmitsWhileProjectFieldHasFocus() async throws {
        let client = RecordingTaskwarriorClient()
        let model = QuickCaptureViewModel(client: client, onCancel: {}, onCreated: {})
        model.prepare(description: "Capture from project field")

        let mounted = mount(model)
        defer { mounted.panel.close() }
        mounted.panel.onSubmit = { Task { await model.submit() } }
        let projectField = try #require(mounted.host.descendant(ofType: NSComboBox.self))
        mounted.panel.makeFirstResponder(projectField)

        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: mounted.panel.windowNumber,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            )
        )
        mounted.panel.sendEvent(event)
        await waitUntil { client.createdDrafts.count == 1 }

        #expect(client.createdDrafts.count == 1)
    }

    @Test func projectEntryIsPreservedWhenReturnSubmits() async throws {
        let client = RecordingTaskwarriorClient()
        let model = QuickCaptureViewModel(client: client, onCancel: {}, onCreated: {})
        model.prepare(description: "Capture with a project")
        model.metadata = TaskwarriorMetadata(
            projects: ["northstar"],
            tags: [],
            priorities: ["H", "M", "L"],
            context: nil
        )

        let mounted = mount(model)
        defer { mounted.panel.close() }
        mounted.panel.onSubmit = { Task { await model.submit() } }
        let projectField = try #require(mounted.host.descendant(ofType: NSComboBox.self))
        #expect(mounted.panel.makeFirstResponder(projectField))
        let editor = try #require(projectField.currentEditor() as? NSTextView)
        editor.insertText("northstar", replacementRange: editor.selectedRange())
        await waitForMainActorWork()

        sendReturn(to: mounted.panel)
        await waitUntil { client.createdDrafts.count == 1 }

        #expect(client.createdDrafts.first?.project == "northstar")
    }

    @Test func projectFieldProcessesReturnBeforePanelSubmits() async throws {
        _ = NSApplication.shared
        let projectField = NSComboBox(frame: NSRect(x: 0, y: 0, width: 130, height: 22))
        projectField.isEditable = true
        let delegate = ReturnRecordingComboBoxDelegate()
        projectField.delegate = delegate
        let panel = QuickCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }
        panel.contentView = projectField
        #expect(panel.makeFirstResponder(projectField))
        var submissionCount = 0
        panel.onSubmit = { submissionCount += 1 }

        sendReturn(to: panel)
        await waitUntil { submissionCount == 1 }

        #expect(delegate.returnCount == 1)
        #expect(submissionCount == 1)
    }

    @Test func dueAndPriorityControlsDoNotOverlap() throws {
        let model = QuickCaptureViewModel(client: RecordingTaskwarriorClient(), onCancel: {}, onCreated: {})
        model.metadata = TaskwarriorMetadata(projects: ["project"], tags: ["tag"], priorities: ["H", "M", "L"], context: nil)

        let mounted = mount(model)
        defer { mounted.panel.close() }
        let dueField = try #require(
            mounted.host.descendants(ofType: NSTextField.self).first { $0.placeholderString == "Due" }
        )
        let priority = try #require(
            mounted.host.descendants(ofType: NSPopUpButton.self).first { $0.itemTitles.contains("Priority") }
        )
        let dueFrame = dueField.convert(dueField.bounds, to: mounted.host)
        let priorityFrame = priority.convert(priority.bounds, to: mounted.host)

        #expect(!dueFrame.intersects(priorityFrame), "Due \(dueFrame) overlaps Priority \(priorityFrame)")
        #expect(priorityFrame.maxX < dueField.convert(dueField.bounds, to: mounted.host).minX)
    }

    @Test func emptyDueDateStaysUnsetWithoutAReferenceDatePicker() throws {
        let model = QuickCaptureViewModel(client: RecordingTaskwarriorClient(), onCancel: {}, onCreated: {})
        let mounted = mount(model)
        defer { mounted.panel.close() }

        #expect(model.draft.due.isEmpty)
        #expect(mounted.host.descendant(ofType: NSDatePicker.self) == nil)
    }

    @Test func tagCompletionDoesNotReplaceTypedPrefixWithAnInteriorMatch() throws {
        var tags: [String] = []
        let coordinator = TagTokenField.Coordinator(
            tags: Binding(get: { tags }, set: { tags = $0 }),
            suggestions: ["hermes"]
        )
        let tokenField = NSTokenField()

        let completions = coordinator.tokenField(
            tokenField,
            completionsForSubstring: "s",
            indexOfToken: 0,
            indexOfSelectedItem: nil
        ) as? [String]

        #expect(completions == [])
    }

    @Test func newlyTypedTagUpdatesBindingAfterAppKitDelegateReturns() async {
        var tags: [String] = []
        let coordinator = TagTokenField.Coordinator(
            tags: Binding(get: { tags }, set: { tags = $0 }),
            suggestions: ["hermes"]
        )
        let tokenField = NSTokenField()
        tokenField.stringValue = "skill"

        (coordinator as NSControlTextEditingDelegate).controlTextDidChange?(
            Notification(name: NSControl.textDidChangeNotification, object: tokenField)
        )

        #expect(tags.isEmpty, "The AppKit delegate must not synchronously re-enter SwiftUI")
        await waitUntil { tags == ["skill"] }
        #expect(tags == ["skill"])
    }

    @Test func priorityKeyboardSelectionUpdatesImmediately() async throws {
        let model = QuickCaptureViewModel(client: RecordingTaskwarriorClient(), onCancel: {}, onCreated: {})
        model.metadata = TaskwarriorMetadata(
            projects: [],
            tags: [],
            priorities: ["H", "M", "L"],
            context: nil
        )

        let mounted = mount(model)
        defer { mounted.panel.close() }
        let priority = try #require(
            mounted.host.descendants(ofType: NSPopUpButton.self).first { $0.itemTitles.contains("Priority") }
        )
        #expect(mounted.panel.makeFirstResponder(priority))
        let start = ContinuousClock.now

        sendKey("m", keyCode: 46, to: mounted.panel)
        await waitUntil { model.draft.priority == "M" }

        let elapsed = start.duration(to: .now)
        #expect(model.draft.priority == "M")
        #expect(elapsed < .milliseconds(250), "Priority update took \(elapsed)")
    }

    @Test func latencyBudgetsUseTheAgreedBoundaries() {
        #expect(
            QuickCaptureLatencyMeasurement(
                selectionLookup: .milliseconds(100),
                invocationToFocusedPanel: .milliseconds(150)
            ).isWithinBudget
        )
        #expect(
            !QuickCaptureLatencyMeasurement(
                selectionLookup: .milliseconds(101),
                invocationToFocusedPanel: .milliseconds(150)
            ).isWithinBudget
        )
        #expect(
            !QuickCaptureLatencyMeasurement(
                selectionLookup: .milliseconds(100),
                invocationToFocusedPanel: .milliseconds(151)
            ).isWithinBudget
        )
    }

    @Test func nativePanelFocusesDescriptionWithinBudget() async throws {
        let controller = QuickCapturePanelController {
            QuickCaptureViewModel(client: RecordingTaskwarriorClient(), onCancel: {}, onCreated: {})
        }
        defer { controller.dismiss() }
        controller.prewarm()
        var measurement: QuickCaptureLatencyMeasurement?
        let trace = QuickCaptureLatency.begin()

        controller.present(description: "Measure focus") {
            measurement = QuickCaptureLatency.finish(trace, selectionLookup: nil)
        }
        await waitUntil { measurement != nil }

        let result = try #require(measurement)
        #expect(
            result.invocationToFocusedPanel <= QuickCaptureLatencyBudget.invocationToFocusedPanel,
            "Native panel focus took \(result.invocationToFocusedPanel)"
        )
    }

    @Test func fullCapturePathStaysWithinBudgetWhenSelectionTimesOut() async throws {
        let controller = QuickCapturePanelController {
            QuickCaptureViewModel(client: RecordingTaskwarriorClient(), onCancel: {}, onCreated: {})
        }
        defer { controller.dismiss() }
        controller.prewarm()
        var measurement: QuickCaptureLatencyMeasurement?
        let trace = QuickCaptureLatency.begin()

        let selection = await SelectedTextReader.firstSelection(
            timeoutNanoseconds: QuickCaptureLatencyBudget.selectionTimeoutNanoseconds
        ) {
            Thread.sleep(forTimeInterval: 0.5)
            return "too late"
        }
        let selectionDuration = QuickCaptureLatency.recordSelectionLookup(for: trace)
        controller.present(description: selection ?? "") {
            measurement = QuickCaptureLatency.finish(trace, selectionLookup: selectionDuration)
        }
        await waitUntil { measurement != nil }

        let result = try #require(measurement)
        #expect(selection == nil)
        #expect(result.isWithinBudget, "Full capture path exceeded its budget: \(result)")
    }

    @Test func panelPrewarmingIsDeferredAndIdempotent() {
        var viewModelCount = 0
        let controller = QuickCapturePanelController {
            viewModelCount += 1
            return QuickCaptureViewModel(
                client: RecordingTaskwarriorClient(),
                onCancel: {},
                onCreated: {}
            )
        }
        defer { controller.dismiss() }

        #expect(viewModelCount == 0)
        controller.prewarm()
        controller.prewarm()
        #expect(viewModelCount == 1)
    }

    private func mount(_ model: QuickCaptureViewModel) -> (panel: QuickCapturePanel, host: NSHostingView<QuickCaptureView>) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: QuickCaptureView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 660, height: 230)
        let panel = QuickCapturePanel(
            contentRect: host.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        return (panel, host)
    }

    private func waitForMainActorWork() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<50 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func sendReturn(to panel: QuickCapturePanel) {
        sendKey("\r", keyCode: 36, to: panel)
    }

    private func sendKey(_ characters: String, keyCode: UInt16, to panel: QuickCapturePanel) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else {
            Issue.record("Could not create key event for \(characters)")
            return
        }
        panel.sendEvent(event)
    }
}

@MainActor
private final class RecordingTaskwarriorClient: TaskwarriorServing {
    private(set) var createdDrafts: [QuickCaptureDraft] = []

    func validateInstallation() async throws -> TaskwarriorInstallation {
        TaskwarriorInstallation(version: "3.4.2")
    }

    func createTask(from draft: QuickCaptureDraft) async throws -> CreatedTask {
        createdDrafts.append(draft)
        return CreatedTask(uuid: UUID(), feedback: "")
    }

    func metadata() async throws -> TaskwarriorMetadata {
        TaskwarriorMetadata(projects: ["project"], tags: ["tag"], priorities: ["H", "M", "L"], context: nil)
    }
}

@MainActor
private final class ReturnRecordingComboBoxDelegate: NSObject, NSComboBoxDelegate, NSControlTextEditingDelegate {
    private(set) var returnCount = 0

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        returnCount += 1
        return true
    }
}

private extension NSView {
    func descendant<T: NSView>(ofType type: T.Type) -> T? {
        descendants(ofType: type).first
    }

    func descendants<T: NSView>(ofType type: T.Type) -> [T] {
        subviews.flatMap { view -> [T] in
            let match = view as? T
            return [match].compactMap { $0 } + view.descendants(ofType: type)
        }
    }
}
