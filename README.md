# TW Mac

A native macOS companion for Taskwarrior. Taskwarrior remains authoritative for task data, configuration, contexts, hooks, urgency, recurrence, and synchronization.

The current implementation is the first internal milestone: menu-bar lifecycle and Quick Capture.

## Requirements

- Apple Silicon Mac running macOS 26 or later
- Xcode 26 or later
- Taskwarrior 3.4 or later

## Build and test

```sh
swift test
./scripts/build-app.sh debug
```

The application bundle is written to `build/TW Mac.app`. Run it during development with:

```sh
./scripts/run-dev-app.sh
```

Development builds use a stable local designated requirement so macOS privacy grants survive rebuilds. Set
`TW_MAC_SIGNING_IDENTITY` to use an installed Apple or local code-signing identity instead.

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
- Taskwarrior installation validation and optional config path
- Launch at Login control

Next:

- First-run onboarding polish and latency instrumentation
- Task Browser milestone

See [the product brief](docs/product-brief.md) for the agreed scope and [the domain glossary](CONTEXT.md) for canonical language.
