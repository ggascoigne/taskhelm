import AppKit
import SwiftUI

struct ProjectColor: Codable, Equatable, Sendable {
    static let minimumVisualDistance = 0.25

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

    func distance(to other: ProjectColor) -> Double {
        let redDelta = red - other.red
        let greenDelta = green - other.green
        let blueDelta = blue - other.blue
        return (redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta).squareRoot()
    }

    func isVisuallyDistinct(from colors: [ProjectColor]) -> Bool {
        colors.allSatisfy { distance(to: $0) >= Self.minimumVisualDistance }
    }

    static func mostDistinct(from colors: [ProjectColor]) -> ProjectColor {
        guard !colors.isEmpty else { return categoricalPalette[0] }

        let paletteChoice = bestCandidate(in: categoricalPalette, from: colors)
        if paletteChoice.distance >= minimumVisualDistance {
            return paletteChoice.color
        }

        let generatedChoice = bestCandidate(in: generatedCandidates, from: colors)
        return generatedChoice.distance > paletteChoice.distance
            ? generatedChoice.color
            : paletteChoice.color
    }

    private static func bestCandidate(
        in candidates: [ProjectColor],
        from colors: [ProjectColor]
    ) -> (color: ProjectColor, distance: Double) {
        candidates
            .map { candidate in
                (candidate, colors.map { candidate.distance(to: $0) }.min() ?? .infinity)
            }
            .max { lhs, rhs in lhs.1 < rhs.1 }!
    }

    private init(hex: UInt32) {
        red = Double((hex >> 16) & 0xff) / 255
        green = Double((hex >> 8) & 0xff) / 255
        blue = Double(hex & 0xff) / 255
    }

    private static let categoricalPalette = [
        ProjectColor(hex: 0x4E79A7), // blue
        ProjectColor(hex: 0xF28E2B), // orange
        ProjectColor(hex: 0xE15759), // red
        ProjectColor(hex: 0x76B7B2), // teal
        ProjectColor(hex: 0x59A14F), // green
        ProjectColor(hex: 0xEDC948), // yellow
        ProjectColor(hex: 0xB07AA1), // purple
        ProjectColor(hex: 0xFF9DA7), // pink
        ProjectColor(hex: 0x9C755F), // brown
        ProjectColor(hex: 0x4D4D4D), // dark gray
        ProjectColor(hex: 0x17BECF), // cyan
        ProjectColor(hex: 0x9467BD), // violet
        ProjectColor(hex: 0xBCBD22), // olive
        ProjectColor(hex: 0x8C564B), // dark brown
    ]

    private static let generatedCandidates: [ProjectColor] = (0..<72).map { index in
        let hue = CGFloat(index % 24) / 24
        let saturation = CGFloat([0.58, 0.72, 0.86][index / 24])
        let color = NSColor(
            calibratedHue: hue,
            saturation: saturation,
            brightness: 0.86,
            alpha: 1
        )
        return ProjectColor(color: Color(nsColor: color))
    }
}
