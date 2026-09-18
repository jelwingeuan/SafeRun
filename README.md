# SafeRun

SafeRun is a native SwiftUI macOS file-automation tool built around one rule: **know what happens before it happens**.

The current milestone provides:

- a SwiftPM macOS application shell with native light/dark appearance support;
- folder picking and folder drag-and-drop with asynchronous metadata scanning;
- strongly typed `SafeRunPlan` and `SafeRunAction` models;
- a local mock planner that turns file-type instructions into structured move/create actions;
- path safety checks, conflict-aware simulation, risk analysis, and real execution inside the selected folder;
- explicit execution confirmation, recovery storage for deletes and replacements, automatic rollback on partial failure, and persistent rollback journals;
- local JSON-backed simulation history;
- unit and temporary-folder integration tests for path validation, risk levels, simulation conflicts, planner output, real moves/deletes/replacements, and rollback behavior.

## Build and test

```sh
swift build
swift test
Scripts/package_app.sh debug
```

The app bundle is assembled as `SafeRun.app` in the project directory. The package script is based on the macOS SwiftPM packaging workflow and uses ad-hoc signing for local builds by default. For a release executable, run `swift build -c release` first and then use `SKIP_BUILD=1 Scripts/package_app.sh release` when the host’s symbol-generation step is unavailable.

The `FLOWMIND` directory at the workspace root is a separate existing project and is intentionally untouched.
