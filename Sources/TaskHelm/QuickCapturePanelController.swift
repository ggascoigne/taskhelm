import AppKit
import SwiftUI

@MainActor
final class QuickCapturePanelController: NSObject, NSWindowDelegate {
    static let panelStyleMask: NSWindow.StyleMask = [.nonactivatingPanel]
    static let panelCornerRadius: CGFloat = 12

    private let makeViewModel: () -> QuickCaptureViewModel
    private let onShowTaskBrowser: () -> Void
    private var panel: QuickCapturePanel?
    private var hostingController: NSHostingController<AnyView>?
    private var viewModel: QuickCaptureViewModel?

    init(
        makeViewModel: @escaping () -> QuickCaptureViewModel,
        onShowTaskBrowser: @escaping () -> Void
    ) {
        self.makeViewModel = makeViewModel
        self.onShowTaskBrowser = onShowTaskBrowser
        super.init()
    }

    convenience init(makeViewModel: @escaping () -> QuickCaptureViewModel) {
        self.init(makeViewModel: makeViewModel, onShowTaskBrowser: {})
    }

    func prewarm() {
        guard panel == nil else { return }

        let model = makeViewModel()
        model.prepare(description: "")
        let panel = makePanel()
        let hostingController = NSHostingController(
            rootView: AnyView(
                QuickCaptureView(model: model, onShowTaskBrowser: onShowTaskBrowser)
                    .id(UUID())
            )
        )
        panel.contentViewController = hostingController
        Self.applyRoundedAppearance(to: panel, hostedView: hostingController.view)
        panel.setContentSize(NSSize(width: 660, height: 230))
        panel.layoutIfNeeded()
        hostingController.view.layoutSubtreeIfNeeded()
        self.panel = panel
        self.hostingController = hostingController
    }

    func present(description: String, onDescriptionFocused: @escaping () -> Void = {}) {
        prewarm()
        let model = makeViewModel()
        model.prepare(description: description)
        viewModel = model

        guard let panel, let hostingController else { return }
        panel.onSubmit = { [weak model] in
            guard let model else { return }
            Task { await model.submit() }
        }
        panel.onCancel = { [weak self] in self?.dismiss() }
        panel.onShowTaskBrowser = onShowTaskBrowser
        hostingController.rootView = AnyView(
            QuickCaptureView(model: model, onShowTaskBrowser: onShowTaskBrowser)
                .id(UUID())
        )
        panel.setContentSize(NSSize(width: 660, height: 230))
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        focusDescription(in: panel, onFocused: onDescriptionFocused)
        Task { await model.loadMetadata() }
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
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 230),
            styleMask: Self.panelStyleMask,
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        return panel
    }

    static func applyRoundedAppearance(to panel: NSPanel, hostedView: NSView) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        hostedView.wantsLayer = true
        hostedView.layer?.cornerRadius = panelCornerRadius
        hostedView.layer?.cornerCurve = .continuous
        hostedView.layer?.masksToBounds = true
    }

    private func focusDescription(
        in panel: QuickCapturePanel,
        attempt: Int = 0,
        onFocused: @escaping () -> Void
    ) {
        panel.contentView?.layoutSubtreeIfNeeded()
        if let field = panel.contentView?.descendants(ofType: NSTextField.self).first(where: {
            $0.placeholderString == "What needs to be done?"
        }), panel.makeFirstResponder(field) {
            onFocused()
            return
        }
        guard attempt < 10 else { return }
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.focusDescription(in: panel, attempt: attempt + 1, onFocused: onFocused)
        }
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

private extension NSView {
    func descendants<T: NSView>(ofType type: T.Type) -> [T] {
        subviews.flatMap { view -> [T] in
            let match = view as? T
            return [match].compactMap { $0 } + view.descendants(ofType: type)
        }
    }
}

final class QuickCapturePanel: NSPanel {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onShowTaskBrowser: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let shortcutModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        if event.modifierFlags.intersection(shortcutModifiers) == .command,
           event.keyCode == 11 {
            onShowTaskBrowser?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

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
