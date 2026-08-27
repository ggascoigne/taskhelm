# TaskHelm contributor guidance

## Product and language

TaskHelm is a native macOS companion for Taskwarrior, not a replacement task
manager. Taskwarrior remains authoritative for task data, configuration,
contexts, hooks, recurrence, urgency, user-defined attributes, and sync.

Use the terminology in [`CONTEXT.md`](CONTEXT.md):

- **Quick Capture** is the transient task-creation panel.
- **Task Browser** is the persistent task-viewing and mutation surface.
- A task **Description** is its one-line Taskwarrior `description`; do not call
  it a title, summary, or note.
- User-facing **Notes** are Taskwarrior **Annotations**. Preserve their
  timestamped, chronological semantics; editing a note replaces its annotation
  with a newly timestamped one.
- **Urgency** and **Priority** are distinct Taskwarrior concepts.

Read [`docs/product-brief.md`](docs/product-brief.md) before changes that alter
product scope or interaction behavior. ADRs in `docs/adr/` are architectural
decisions, not optional suggestions.

## Architecture

- The project is Swift 6.2, targeting Apple Silicon Macs running macOS 26+.
- Use SwiftUI for ordinary UI. Use AppKit only where native macOS integration
  requires it (for example global shortcuts, panels, focus, menu-bar lifecycle,
  and Accessibility APIs).
- `Sources/TaskHelmCore/` owns Taskwarrior models, process execution, and CLI
  integration. `Sources/TaskHelm/` owns application, window, view, and
  view-model behavior.
- Keep views thin and put async/task state in `@MainActor` view models. Depend
  on the existing protocols (`TaskwarriorServing`, `TaskBrowsing`, and
  `TaskMutating`) so behavior remains testable with recording clients.

## Taskwarrior integration

- Invoke the configured Taskwarrior executable directly with structured argument
  arrays. Never create shell command strings, use a shell, or read/write
  Taskwarrior's SQLite data directly.
- Preserve unknown attributes and user-defined attributes. Do not discard data
  merely because the client does not display it.
- Empty Quick Capture metadata defers to Taskwarrior Context, `.taskrc` defaults,
  and hooks. Do not emulate those defaults in the client.
- Do not invoke `task sync`; synchronization is externally managed.
- Browser mutations use operation-scoped, conflict-safe undo. Do not replace it
  with Taskwarrior's global `task undo`.

## UI and interaction

- Prefer native Mac controls, SF Symbols, semantic colors, and standard macOS
  keyboard behavior. Do not imitate terminal chrome or Taskwarrior CLI colors.
- Quick Capture is intentionally transient and performance-sensitive: panel
  visibility must not wait on Taskwarrior, selected-text lookup has a 100 ms
  budget, and hotkey-to-focused-panel has a 150 ms budget.
- Keep destructive actions behind native confirmation. Keep failed Quick Capture
  submissions open, with entered values preserved and an actionable error.
- Maintain accessibility labels for custom or non-obvious controls and preserve
  keyboard focus/navigation when changing SwiftUI/AppKit boundaries.

## Build and test

Run the smallest relevant tests while iterating, then run the full suite before
hand-off:

```sh
swift test
./scripts/build-app.sh debug
```

The development bundle is written to `build/TaskHelm.app`. Run it with:

```sh
./scripts/run-dev-app.sh
```

Add focused regression tests alongside changes:

- Core Taskwarrior behavior: `Tests/TaskHelmCoreTests/`
- App, UI, panel, and view-model behavior: `Tests/TaskHelmTests/`

Use test doubles for CLI behavior in unit tests. The integration tests require a
real, isolated Taskwarrior environment; do not weaken them to accommodate local
state.

## Scope discipline

- Keep changes small and native to the existing architecture.
- Do not add app-owned networking, telemetry, crash uploads, automatic updates,
  cloud storage, or a Taskwarrior setup wizard without an explicit product
  decision.
- Treat deferred capabilities in the product brief as out of scope unless the
  task explicitly brings them in.
