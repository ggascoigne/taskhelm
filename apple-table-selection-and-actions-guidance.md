# Apple Guidance for Tables, Selection, and Actions

## Summary

Apple's guidance points toward a selection-driven table, especially on macOS: rows primarily present data and establish a selection, while commands that operate on the selection generally live in a toolbar, menu, or context menu.

The core design principle is:

> Select the object first, then act on it through stable, contextual command surfaces instead of turning every row into a miniature toolbar.

## Table and row behavior

For a macOS table displaying rows of data, the conventional behavior is:

- A single click selects a row.
- The entire row receives the selection highlight, rather than only one cell.
- Command-click and Shift-click support multiple selection when appropriate.
- A double-click may perform the row's primary action, such as opening or editing it.
- Actions apply to the current selection, including all selected rows when the action supports bulk operation.
- A secondary click opens a contextual menu for the clicked row or current selection.

Apple says whole-row highlighting is generally easier to understand. On macOS, an active selection uses the app's accent-color highlight, while an inactive selection uses a subdued gray highlight.

## Where actions should appear

Use the following hierarchy for presenting actions:

1. Put frequently used actions in the toolbar.
2. Put less common but relevant actions in a More menu.
3. Offer contextual shortcuts in a secondary-click context menu.
4. On macOS, make the complete command set available through the menu bar and provide keyboard shortcuts for frequent commands.
5. Use inline row controls only when a control represents a directly manipulable row property or an exceptionally frequent and unambiguous action.

Toolbars are the standard location for commands that act on content in the current view. Actions should be prioritized, limited to avoid clutter, grouped logically, and represented with recognizable system symbols where possible.

Context menus are supplementary. They should contain a small number of relevant, commonly needed commands, but they should not be the only way to access those commands. On macOS, context-menu commands should also be available through the menu bar and, when appropriate, the toolbar.

## Inline buttons in rows

Apple does not state an absolute prohibition against row buttons. However, permanently displaying controls such as **Edit**, **Delete**, and **More** in every row is generally less consistent with native Mac table design because it:

- Competes visually with the row's data.
- Makes the distinction between selecting and activating a row less clear.
- Consumes useful column space.
- Makes actions on multiple selected rows awkward.
- Repeats identical controls throughout the table.

A more native arrangement is:

```text
Toolbar:  +   Edit   Share   Delete   More
                    ↓ acts on selection

┌──────────────────────────────────────────┐
│ Name              Status       Modified   │
├──────────────────────────────────────────┤
│ Item A             Active       Today      │
│ Item B             Paused       Yesterday  │ ← selected
│ Item C             Active       Monday     │
└──────────────────────────────────────────┘
```

Actions that require a selection should remain visible but unavailable when no applicable item is selected. This preserves discoverability. Regular menu commands generally appear dimmed when unavailable. Context menus behave differently: they should omit commands that are irrelevant to the current context.

## Selection is not persistent state

Selection means "the object that subsequent commands affect." It should not represent persistent data state such as enabled, favorite, approved, or the current default.

Represent persistent state explicitly with an appropriate control or indicator, such as:

- A checkmark
- A toggle
- A status value
- A badge
- An icon

Apple distinguishes between navigation tables and option tables:

- A navigation table generally keeps the selected row highlighted to clarify the current path.
- An option table generally highlights a row briefly, then displays a checkmark or similar indicator to communicate the selected state.

## Recommended implementation

For a Mac table of records:

- Make the full row selectable.
- Keep selected rows visibly highlighted.
- Support standard single-, range-, and multiple-selection interactions where appropriate.
- Show common actions once in the toolbar and have them track the current selection.
- Keep inapplicable toolbar or menu actions visible but disabled.
- Support secondary-click context actions.
- Put the complete command set in the menu bar.
- Add keyboard shortcuts for frequent commands.
- Use double-click for the natural primary action.
- Reserve inline controls for genuine row values, such as an enabled toggle, or a single exceptionally useful quick action.
- Make destructive actions visually distinct and provide undo or confirmation according to how reversible the operation is.

## Apple sources

- [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)
- [Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection/)
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)
- [Menus](https://developer.apple.com/design/human-interface-guidelines/menus)
- [SwiftUI selection-based context menus and primary actions](https://developer.apple.com/documentation/swiftui/view/contextmenu%28forselectiontype%3Amenu%3Aprimaryaction%3A%29)

## Interpretation note

Apple's guidelines describe the component behaviors and placement principles above, but they do not contain a single blanket rule saying that all row actions must be outside the row. The recommendation to prefer selection-based toolbar and menu actions over repeated inline action clusters is a synthesis of Apple's table, selection, toolbar, menu, and context-menu guidance.
