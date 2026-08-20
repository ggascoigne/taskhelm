import AppKit
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: $shortcut)
    }

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.shortcut = shortcut
        view.onChange = { context.coordinator.shortcut.wrappedValue = $0 }
        return view
    }

    func updateNSView(_ view: RecorderNSView, context: Context) {
        view.shortcut = shortcut
        view.needsDisplay = true
    }

    final class Coordinator {
        var shortcut: Binding<GlobalShortcut>

        init(shortcut: Binding<GlobalShortcut>) {
            self.shortcut = shortcut
        }
    }
}

final class RecorderNSView: NSView {
    var shortcut = GlobalShortcut.defaultQuickCapture
    var onChange: ((GlobalShortcut) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 28) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            isRecording = false
            needsDisplay = true
            return
        }

        let candidate = GlobalShortcut(event: event)
        guard candidate.hasRequiredModifier else {
            NSSound.beep()
            return
        }

        shortcut = candidate
        onChange?(candidate)
        isRecording = false
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text = isRecording ? "Type shortcut…" : shortcut.displayName
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}
