import AppKit
import SwiftUI

@MainActor
final class QuickCapturePanelController: NSObject, NSWindowDelegate {
    private let makeViewModel: () -> QuickCaptureViewModel
    private var panel: QuickCapturePanel?
    private var viewModel: QuickCaptureViewModel?

    init(makeViewModel: @escaping () -> QuickCaptureViewModel) {
        self.makeViewModel = makeViewModel
    }

    func present(description: String) {
        let model = makeViewModel()
        model.prepare(description: description)
        viewModel = model

        let panel = panel ?? makePanel()
        panel.onSubmit = { [weak model] in
            guard let model else { return }
            Task { await model.submit() }
        }
        panel.onCancel = { [weak self] in self?.dismiss() }
        panel.contentViewController = NSHostingController(rootView: QuickCaptureView(model: model))
        panel.setContentSize(NSSize(width: 660, height: 190))
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        viewModel = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
    }

    private func makePanel() -> QuickCapturePanel {
        let panel = QuickCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 190),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + visibleFrame.height * 0.68
        )
        panel.setFrameOrigin(origin)
    }
}

final class QuickCapturePanel: NSPanel {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else {
            super.sendEvent(event)
            return
        }

        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        if event.modifierFlags.intersection(disallowedModifiers).isEmpty,
           event.keyCode == 36 || event.keyCode == 76 {
            if isEditingComboBox {
                super.sendEvent(event)
                DispatchQueue.main.async { [weak self] in self?.onSubmit?() }
                return
            }
            makeFirstResponder(nil)
            onSubmit?()
            return
        }

        if event.keyCode == 53 {
            onCancel?()
            return
        }

        super.sendEvent(event)
    }

    private var isEditingComboBox: Bool {
        if firstResponder is NSComboBox {
            return true
        }
        guard let fieldEditor = firstResponder as? NSTextView else { return false }
        return fieldEditor.delegate is NSComboBox
    }
}
