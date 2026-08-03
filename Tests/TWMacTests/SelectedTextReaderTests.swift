import Foundation
import Testing
@testable import TWMac

@Suite("Selected text permission")
struct SelectedTextReaderTests {
    @Test func opensAccessibilitySettingsWhenPermissionIsNotGranted() {
        var settingsWereOpened = false
        let reader = SelectedTextReader(
            requestTrust: { false },
            openAccessibilitySettings: { settingsWereOpened = true }
        )

        #expect(!reader.requestPermission())
        #expect(settingsWereOpened)
    }

    @Test func doesNotOpenAccessibilitySettingsWhenAlreadyTrusted() {
        var settingsWereOpened = false
        let reader = SelectedTextReader(
            requestTrust: { true },
            openAccessibilitySettings: { settingsWereOpened = true }
        )

        #expect(reader.requestPermission())
        #expect(!settingsWereOpened)
    }

    @Test func preparesElectronSourceBeforeReadingSelection() {
        var sourceIsPrepared = false

        let selection = SelectedTextReader.readSelectedText(
            processIdentifier: 42,
            prepareSource: { _ in sourceIsPrepared = true },
            readSelection: { _ in sourceIsPrepared ? "selected in VS Code" : nil }
        )

        #expect(selection == "selected in VS Code")
    }

    @Test func readsTextMarkerSelectionFromAncestorWebArea() {
        let selection = SelectedTextReader.extractSelectedText(
            startingAt: 0,
            attribute: { element, attribute in
                element == 1 && attribute == "AXSelectedTextMarkerRange" ? "marker-range" : nil
            },
            stringValue: { $0 },
            parameterizedString: { element, attribute, value in
                element == 1 && attribute == "AXStringForTextMarkerRange" && value == "marker-range"
                    ? "selected in VS Code"
                    : nil
            },
            parent: { $0 == 0 ? 1 : nil }
        )

        #expect(selection == "selected in VS Code")
    }

    @Test func retriesWhileElectronBuildsItsAccessibilityTree() {
        var attempts = 0

        let selection = SelectedTextReader.readSelectedText(
            processIdentifier: 42,
            prepareSource: { _ in },
            readSelection: { _ in
                attempts += 1
                return attempts == 2 ? "available after activation" : nil
            }
        )

        #expect(selection == "available after activation")
    }

    @Test func selectionLookupReturnsAtTheConfiguredDeadline() async {
        let start = ContinuousClock.now

        let selection = await SelectedTextReader.firstSelection(
            timeoutNanoseconds: QuickCaptureLatencyBudget.selectionTimeoutNanoseconds
        ) {
            Thread.sleep(forTimeInterval: 0.5)
            return "too late"
        }

        let elapsed = start.duration(to: .now)
        #expect(selection == nil)
        #expect(elapsed >= .milliseconds(60), "Selection lookup returned prematurely after \(elapsed)")
        #expect(
            elapsed <= QuickCaptureLatencyBudget.selectionLookup,
            "Selection lookup exceeded its 100 ms budget: \(elapsed)"
        )
    }

}
