import AppKit
import SwiftUI

struct AutocompleteTextField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String
    var suggestions: [String]

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.delegate = context.coordinator
        comboBox.isEditable = true
        comboBox.completes = true
        comboBox.placeholderString = prompt
        comboBox.numberOfVisibleItems = 8
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        context.coordinator.text = $text
        if comboBox.stringValue != text {
            comboBox.stringValue = text
        }
        comboBox.removeAllItems()
        comboBox.addItems(withObjectValues: suggestions)
    }

    final class Coordinator: NSObject, NSComboBoxDelegate, NSControlTextEditingDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            text.wrappedValue = comboBox.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            text.wrappedValue = comboBox.stringValue
        }
    }
}

struct TagTokenField: NSViewRepresentable {
    @Binding var tags: [String]
    var suggestions: [String]

    func makeCoordinator() -> Coordinator {
        Coordinator(tags: $tags, suggestions: suggestions)
    }

    func makeNSView(context: Context) -> NSTokenField {
        let tokenField = NSTokenField()
        tokenField.delegate = context.coordinator
        tokenField.placeholderString = "Tags"
        tokenField.tokenStyle = .rounded
        tokenField.tokenizingCharacterSet = CharacterSet(charactersIn: ",")
        return tokenField
    }

    func updateNSView(_ tokenField: NSTokenField, context: Context) {
        context.coordinator.tags = $tags
        context.coordinator.suggestions = suggestions
        if !tokenField.currentEditorHasMarkedText {
            tokenField.objectValue = tags
        }
    }

    final class Coordinator: NSObject, NSTokenFieldDelegate {
        var tags: Binding<[String]>
        var suggestions: [String]

        init(tags: Binding<[String]>, suggestions: [String]) {
            self.tags = tags
            self.suggestions = suggestions
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let tokenField = notification.object as? NSTokenField else { return }
            tags.wrappedValue = Self.strings(from: tokenField.objectValue)
        }

        func tokenField(
            _ tokenField: NSTokenField,
            completionsForSubstring substring: String,
            indexOfToken tokenIndex: Int,
            indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?
        ) -> [Any]? {
            suggestions.filter { $0.localizedCaseInsensitiveContains(substring) }
        }

        private static func strings(from value: Any?) -> [String] {
            if let values = value as? [String] {
                return values.map(trimmed).filter { !$0.isEmpty }
            }
            if let value = value as? String {
                return value.split(separator: ",").map { trimmed(String($0)) }.filter { !$0.isEmpty }
            }
            return []
        }

        private static func trimmed(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

private extension NSTokenField {
    var currentEditorHasMarkedText: Bool {
        (currentEditor() as? NSTextView)?.hasMarkedText() == true
    }
}
