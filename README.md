# TaskHelm

A native macOS companion for Taskwarrior. Taskwarrior remains authoritative for task data, configuration, contexts, hooks, urgency, recurrence, and synchronization.

The current implementation includes Quick Capture and a native Task Browser with editing, bulk actions, and conflict-safe Undo.

## Requirements

- Apple Silicon Mac running macOS 26 or later
- Xcode 26 or later
- Taskwarrior 3.4 or later

## Build and test

```sh
swift test
./scripts/build-app.sh debug
```

The application bundle is written to `build/TaskHelm.app`. Run it during development with:

```sh
./scripts/run-dev-app.sh
```

Development builds use a stable local designated requirement so macOS privacy grants survive rebuilds. Set
`TASKHELM_SIGNING_IDENTITY` to use an installed Apple or local code-signing identity instead.

Quick Capture defaults to `Control-Option-Space`. Its shortcut, Taskwarrior executable, optional taskrc path, selected-text capture, and Launch at Login behavior are configured in Settings.

VS Code requires `"editor.accessibilitySupport": "on"` followed by **Developer: Reload Window** before editor or integrated-terminal selections are exposed to Quick Capture.

## Status

Implemented:

- Native menu-bar app and floating Quick Capture panel
- Literal Description capture with Project, Tags, Due, and configured Priority fields
- Taskwarrior contexts/defaults/hooks preserved through CLI invocation
- Isolated Taskwarrior integration tests
- Configurable global shortcut
- Optional Accessibility-based selected-text capture with a 100 ms timeout
- Prewarmed Quick Capture panel with local signpost latency instrumentation
- Taskwarrior installation validation and optional config path
- Launch at Login control
- First-run onboarding with automatic Taskwarrior validation
- Persistent three-region Task Browser window
- Next, Waiting, and Completed views with Project, Tag, and raw Taskwarrior filtering
- Urgency-first task table with remembered client-local sorting
- Resizable details pane that can be placed on the right or bottom, with its layout and size remembered between sessions
- Full-fidelity read-only inspector, manual refresh, focus refresh, and five-second visible refresh
- Inspector editing for Description, Project, Tags, Due, and Priority
- Notes-style chronological annotations with multiline capture, editing, confirmed deletion, and URL linking
- Project and Tag autocomplete plus configured Priority choices while editing
- Complete, Start/Stop, and confirmed Delete actions
- Multi-selection Start, Stop, Complete, and confirmed Delete actions
- Bulk set Project and add/remove Tags with one-level Undo
- Selection-driven toolbar, Task menu, secondary-click commands, and double-click Edit
- Conflict-safe, operation-scoped one-level Undo through Taskwarrior import

The agreed Quick Capture and Task Browser milestones are implemented.

Quick Capture emits local `QuickCaptureLatency` signposts for `SelectionLookup` and
`InvocationToFocusedPanel`. They can be inspected with Instruments’ Points of Interest template;
each includes elapsed milliseconds and whether the 100 ms selection and 150 ms focus budgets were met.
No measurements leave the Mac.

Browser refresh re-reads local Taskwarrior data after client mutations, when the window regains focus,
on request, and approximately every five seconds while visible. Synchronization with a remote Taskwarrior
replica remains externally managed and is not triggered by TaskHelm.

See [the product brief](docs/product-brief.md) for the agreed scope and [the domain glossary](CONTEXT.md) for canonical language.
