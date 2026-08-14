import AppKit
import SwiftUI

struct ProjectColor: Codable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(color: Color) {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        red = Double(converted.redComponent)
        green = Double(converted.greenComponent)
        blue = Double(converted.blueComponent)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    static func random() -> ProjectColor {
        let color = NSColor(
            calibratedHue: .random(in: 0..<1),
            saturation: .random(in: 0.55...0.78),
            brightness: .random(in: 0.72...0.92),
            alpha: 1
        )
        return ProjectColor(color: Color(nsColor: color))
    }
}
