import AppKit
import SwiftUI

struct ProjectColorWell: NSViewRepresentable {
    @Binding var color: Color
    let label: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSColorWell {
        let well = CircularNSColorWell()
        well.supportsAlpha = false
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.setAccessibilityLabel(label)
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.parent = self
        let updatedColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        if well.color != updatedColor {
            well.color = updatedColor
            well.needsDisplay = true
        }
        well.setAccessibilityLabel(label)
    }

    final class Coordinator: NSObject {
        var parent: ProjectColorWell

        init(parent: ProjectColorWell) {
            self.parent = parent
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            parent.color = Color(nsColor: sender.color)
        }
    }
}

private final class CircularNSColorWell: NSColorWell {
    private let diameter: CGFloat = 13

    init() {
        super.init(frame: .zero)
        colorWellStyle = .minimal
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: diameter, height: diameter)
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75))
        color.setFill()
        circle.fill()
        (isActive ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        circle.lineWidth = isActive ? 1.5 : 1
        circle.stroke()
    }
}
