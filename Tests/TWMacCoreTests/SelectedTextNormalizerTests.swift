import Testing
@testable import TWMacCore

@Suite("Selected text normalization")
struct SelectedTextNormalizerTests {
    @Test func collapsesWhitespaceWithoutTruncating() {
        let selected = "  First line\n\nsecond\tline   with spaces  "

        #expect(SelectedTextNormalizer.normalize(selected) == "First line second line with spaces")
    }

    @Test func preservesUnicode() {
        #expect(SelectedTextNormalizer.normalize("  café 🧠  ") == "café 🧠")
    }
}
