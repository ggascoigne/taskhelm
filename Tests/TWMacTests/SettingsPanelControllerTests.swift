import AppKit
import Testing
@testable import TWMac

@MainActor
@Suite("Settings panel", .serialized)
struct SettingsPanelControllerTests {
    @Test func usesFloatingTransientUtilityPanel() {
        let panel = SettingsPanelController.makePanel()
        defer { panel.close() }

        #expect(panel.isFloatingPanel)
        #expect(panel.level == .floating)
        #expect(panel.styleMask.contains(.utilityWindow))
        #expect(panel.collectionBehavior.contains(.transient))
    }

    @Test func isLargeEnoughForSettingsContent() {
        let panel = SettingsPanelController.makePanel()
        defer { panel.close() }

        #expect(panel.contentLayoutRect.size.width == SettingsPanelController.contentSize.width)
        #expect(panel.contentLayoutRect.size.height == SettingsPanelController.contentSize.height)
    }

    @Test func centersWithinTheSelectedScreen() {
        let panel = SettingsPanelController.makePanel()
        defer { panel.close() }
        let visibleFrame = NSRect(x: 1_440, y: 24, width: 1_920, height: 1_056)

        SettingsPanelController.center(panel, in: visibleFrame)

        #expect(abs(panel.frame.midX - visibleFrame.midX) < 0.5)
        #expect(abs(panel.frame.midY - visibleFrame.midY) < 0.5)
    }
}
