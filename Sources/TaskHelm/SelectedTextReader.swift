import AppKit
import ApplicationServices
import Foundation

struct SelectedTextReader {
    private let requestTrust: () -> Bool
    private let openAccessibilitySettings: () -> Void

    init(
        requestTrust: @escaping () -> Bool = SelectedTextReader.requestSystemTrust,
        openAccessibilitySettings: @escaping () -> Void = SelectedTextReader.openSystemAccessibilitySettings
    ) {
        self.requestTrust = requestTrust
        self.openAccessibilitySettings = openAccessibilitySettings
    }

    func requestPermission() -> Bool {
        let isTrusted = requestTrust()
        if !isTrusted {
            openAccessibilitySettings()
        }
        return isTrusted
    }

    private static func requestSystemTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func openSystemAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    func selectedText(
        timeoutNanoseconds: UInt64 = QuickCaptureLatencyBudget.selectionTimeoutNanoseconds
    ) async -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier

        return await Self.firstSelection(timeoutNanoseconds: timeoutNanoseconds) {
            Self.readSelectedText(
                processIdentifier: processIdentifier,
                prepareSource: Self.enableAccessibility,
                readSelection: Self.readFocusedSelection
            )
        }
    }

    static func firstSelection(
        timeoutNanoseconds: UInt64,
        readSelection: @escaping @Sendable () -> String?
    ) async -> String? {
        await withCheckedContinuation { continuation in
            let completion = SelectionCompletion(continuation: continuation)

            Task.detached(priority: .userInitiated) {
                completion.resume(with: readSelection())
            }
            Task.detached {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                completion.resume(with: nil)
            }
        }
    }

    static func readSelectedText(
        processIdentifier: pid_t?,
        prepareSource: (pid_t) -> Void,
        readSelection: (pid_t?) -> String?
    ) -> String? {
        if let processIdentifier {
            prepareSource(processIdentifier)
        }
        for attempt in 0..<3 {
            if let selection = readSelection(processIdentifier) {
                return selection
            }
            if attempt < 2 {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        return nil
    }

    private static func enableAccessibility(for processIdentifier: pid_t) {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, true as CFTypeRef)
    }

    private static func readFocusedSelection(processIdentifier: pid_t?) -> String? {
        let focusRoot = processIdentifier.map(AXUIElementCreateApplication) ?? AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusRoot,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success, let focusedValue else {
            return nil
        }

        let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)
        return extractSelectedText(
            startingAt: focusedElement,
            attribute: copyAttribute,
            stringValue: { $0 as? String },
            parameterizedString: copyParameterizedString,
            parent: copyParent
        )
    }

    static func extractSelectedText<Element, Value>(
        startingAt element: Element,
        attribute: (Element, String) -> Value?,
        stringValue: (Value) -> String?,
        parameterizedString: (Element, String, Value) -> String?,
        parent: (Element) -> Element?
    ) -> String? {
        var current: Element? = element
        for _ in 0..<8 {
            guard let element = current else { break }
            if let value = attribute(element, kAXSelectedTextAttribute),
               let text = stringValue(value),
               !text.isEmpty {
                return text
            }
            let rangeAttributes = [
                ("AXSelectedTextMarkerRange", "AXStringForTextMarkerRange"),
                (kAXSelectedTextRangeAttribute, kAXStringForRangeParameterizedAttribute),
            ]
            for (rangeAttribute, stringAttribute) in rangeAttributes {
                if let range = attribute(element, rangeAttribute),
                   let text = parameterizedString(element, stringAttribute, range),
                   !text.isEmpty {
                    return text
                }
            }
            current = parent(element)
        }
        return nil
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func copyParameterizedString(
        _ element: AXUIElement,
        _ attribute: String,
        _ parameter: CFTypeRef
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute as CFString,
            parameter,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    private static func copyParent(_ element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(element, kAXParentAttribute) else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

}

private final class SelectionCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    init(continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func resume(with value: String?) {
        let pending = lock.withLock { () -> CheckedContinuation<String?, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
