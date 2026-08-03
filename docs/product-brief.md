# TW Mac Product Brief

## Product intent

TW Mac is a clean native Mac interface for experienced Taskwarrior users. It improves capture and browsing without becoming a separate task manager: Taskwarrior remains authoritative for task data, configuration, contexts, hooks, urgency, recurrence, synchronization, and user-defined attributes.

The app is initially built for Guy's workflow, with enough configuration and error handling to remain useful to other experienced Taskwarrior users. Public release timing is deliberately undefined; the app should be dogfooded before it is packaged for others.

## Platform and distribution

- Native Swift implementation using SwiftUI with targeted AppKit integration.
- macOS 26 or later on Apple Silicon only.
- Menu-bar resident, with optional Launch at Login.
- Direct distribution outside the Mac App Store; signing and notarization are expected before sharing.
- MIT/open-source release posture.
- `TW Mac` and `tw-mac` are working identities; public branding is deferred.
- No app-owned networking in the initial product: no telemetry, crash uploads, update checks, or cloud service.

## Taskwarrior integration

- Taskwarrior 3.4 or later is required.
- Use supported Taskwarrior CLI integration only; never read or write Taskwarrior's SQLite database.
- Query machine-readable JSON through Taskwarrior and perform mutations through supported Taskwarrior commands.
- Invoke the executable directly with structured arguments, never through shell command composition.
- Preserve unknown UDAs and all data the client does not understand.
- Support one configured Taskwarrior environment in the initial product: one executable path and one optional config path.
- Auto-detect sensible defaults and allow both paths to be changed in Settings.
- Blank client metadata fields defer to active Context, `.taskrc` defaults, and hooks.
- Synchronization remains external to the Mac client initially. Browser refreshes re-read local Taskwarrior data but do not invoke `task sync`; Quick Capture never waits for sync.

## Internal milestone 1: Quick Capture

Quick Capture is independently useful and is implemented before Task Browser.

### Lifecycle and invocation

- The default global shortcut is configurable and initially set to `Control-Option-Space`.
- A registration conflict is explained in Settings rather than failing silently.
- The shortcut opens a transient, non-activating floating panel on the active display.
- The panel returns focus to the originating app when dismissed.
- Clicking elsewhere does not dismiss it.
- Enter submits; Escape discards.
- The successful disappearance of the panel is sufficient feedback: no notification or sound.
- A failed Taskwarrior operation keeps the panel open, preserves all values, and shows an actionable error.

### Selection capture

- Selected plain text may seed Description when the user enables the feature and grants Accessibility permission.
- Selection capture uses macOS Accessibility APIs; it never synthesizes Copy or mutates the clipboard.
- Failure, unsupported source controls, denial, or timeout opens an empty panel.
- Selected text is trimmed and whitespace-normalized into the one-line Description without silent truncation or automatic splitting.
- Rich text, images, source application metadata, browser URLs, and file paths are out of scope.
- Long-form Notes and automatic Description/Notes splitting are deferred.

### Fields and interaction

- Description is literal text, never implicit Taskwarrior command syntax.
- Project, Tags, Due, and Priority are visible as a compact metadata row beneath Description.
- Description receives initial focus; Tab and Shift-Tab navigate metadata controls.
- Project and Tags autocomplete existing Taskwarrior values while allowing new values.
- Project preserves Taskwarrior hierarchy syntax; Tags supports multiple values and excludes virtual/reserved tags from assignment suggestions.
- Due accepts Taskwarrior date expressions and also offers a native calendar picker. Taskwarrior validates and resolves expressions.
- Priority derives its allowed values from Taskwarrior configuration rather than assuming `H/M/L`.
- Active Context is visible because it may affect captured tasks.

### Performance requirement

- Hotkey to focused panel: at most 150 ms under normal local conditions.
- Selected-text lookup receives at most 100 ms before falling back to an empty Description.
- No Taskwarrior process runs before the panel is visible.
- Submission runs asynchronously without blocking the interface.

## Internal milestone 2: Task Browser

### Window and structure

- One persistent Browser window; reopening focuses the existing window.
- Native three-region layout:
  - Sidebar for built-in views, Projects, and Tags.
  - Dense task table.
  - Inspector for the selected task.
- Quick Capture remains an independent panel.
- Use native Mac controls, typography, SF Symbols, and semantic colors; do not imitate terminal chrome or parse Taskwarrior terminal color rules.
- Quick Capture is spacious; the Browser is compact but not spreadsheet-like.

### Dataset, views, filtering, and sorting

- The default view follows the configured `report.next.filter` and active Context.
- Built-in views are Next, Waiting, and Completed.
- Deleted tasks and hidden recurrence templates are excluded initially.
- Sidebar Project and Tag filters refine the active built-in view.
- A raw Taskwarrior filter bar provides live expert filtering; Taskwarrior evaluates the expression.
- Saved custom filters are deferred.
- Default order is Urgency descending, not literal Priority.
- Table sorting is client-local and remembered between Browser sessions; clicking the Urgency column restores Urgency ordering.
- Refresh after client mutations, whenever the Browser regains focus, manually on request, and approximately every five seconds while visible.
- External changes are always re-read through Taskwarrior rather than detected by interpreting its database.

### Table and inspector

- Default columns: Description, Project, Tags, Due, Priority, and Urgency.
- Active, blocked, recurring, and annotated states appear as compact Description indicators.
- Columns may be resized and reordered; choosing arbitrary columns is deferred.
- The inspector displays full exported fidelity:
  - Known attributes receive native formatting.
  - Annotations are chronological and initially read-only.
  - Unknown and namespaced UDAs appear read-only.
- Inspector edits use explicit Edit and Save/Cancel, applying changed fields in one Taskwarrior mutation.

### Initial mutations

- Edit Description, Project, Tags, Due, and Priority.
- Complete.
- Start and stop.
- Delete, always after native confirmation.
- Create through Quick Capture.
- Multi-selection bulk actions: Complete, Delete, set Project, and add/remove Tags.
- Dependencies, recurrence, annotations, arbitrary UDAs, and other fields are initially read-only.
- The app uses its own confirmation for destructive operations and disables duplicate CLI confirmation for that invocation.

### Undo

- All Browser mutations support one level of Undo, including inspector edits, start/stop, bulk changes, Complete, and Delete.
- Undo is available through a visible action and standard `Command-Z`.
- Capture full Taskwarrior state before and after the mutation and retain the operation's complete footprint, including recurrence or hook side effects.
- Restore only that footprint through Taskwarrior.
- If sync or another client changes affected records after the operation, refuse to undo rather than overwrite newer work.
- Do not use Taskwarrior's global `task undo` command, which could reverse an intervening external action.

### Keyboard behavior

- Follow standard macOS navigation and commands.
- No Vim compatibility layer, modal editing, or configurable Browser keymap.

## Settings and onboarding

First run should:

1. Locate and validate Taskwarrior 3.4 or later.
2. Allow executable and optional config paths to be corrected.
3. Present and record the configurable global shortcut.
4. Recommend and request Launch at Login.
5. Explain selected-text capture and request Accessibility permission only if enabled.

The app does not install Taskwarrior, create a beginner workflow, or provide a Taskwarrior setup wizard.

## Deferred possibilities

- Long-form Notes, potentially backed by a namespaced UDA after its interoperability is designed.
- Annotation editing.
- Dependencies and recurrence editing.
- Arbitrary UDA editing.
- Saved filters.
- Multiple Taskwarrior environments or profiles.
- Source application, URL, file, rich-text, and image capture.
- Public branding, notarized releases, and Homebrew distribution.
- Intel Mac and older macOS support.
- Automatic synchronization.
- An explicit in-app Taskwarrior Sync command.

## References

- [Taskwarrior third-party application guidelines](https://taskwarrior.org/docs/3rd-party/)
- [Taskwarrior 3.4.2 command reference](https://taskwarrior.org/docs/man/task.1/)
- [Taskwarrior task representation](https://taskwarrior.org/docs/task/)
- [Taskwarrior recurrence model](https://taskwarrior.org/docs/recurrence/)
- [Taskwarrior synchronization](https://taskwarrior.org/docs/sync/)
- [taskwarrior-tui](https://github.com/kdheepak/taskwarrior-tui)
- [Apple Accessibility selected-text attribute](https://developer.apple.com/documentation/applicationservices/kaxselectedtextattribute)
- [Apple App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
