import AppKit
import SwiftUI

struct PriorityPicker: NSViewRepresentable {
    @Binding var selection: String
    var priorities: [String]

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> PriorityPopUpButton {
        let button = PriorityPopUpButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.setAccessibilityLabel("Priority")
        return button
    }

    func updateNSView(_ button: PriorityPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        let titles = ["Priority"] + priorities
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        button.priorityValues = priorities

        let title = priorities.contains(selection) ? selection : "Priority"
        if button.titleOfSelectedItem != title {
            button.selectItem(withTitle: title)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<String>

        init(selection: Binding<String>) {
            self.selection = selection
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            selection.wrappedValue = sender.indexOfSelectedItem > 0 ? sender.titleOfSelectedItem ?? "" : ""
        }
    }
}

final class PriorityPopUpButton: NSPopUpButton {
    var priorityValues: [String] = []

    override func keyDown(with event: NSEvent) {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty,
              let characters = event.charactersIgnoringModifiers,
              characters.count == 1,
              let match = priorityValues.first(where: {
                  $0.count == 1 && $0.caseInsensitiveCompare(characters) == .orderedSame
              }) else {
            super.keyDown(with: event)
            return
        }

        selectItem(withTitle: match)
        sendAction(action, to: target)
    }
}
