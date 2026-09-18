# SafeRun

SafeRun is a native macOS file-automation app built around one rule: preview every change before it happens. It turns a plain-language request into a structured plan, validates it locally, simulates the result without touching your files, and only executes after your explicit confirmation.

## What 1.0.0 does

- Uses the OpenAI Responses API with Structured Outputs to create plans. The default model is `gpt-5.6-terra`; Luna, Terra, and Sol are selectable in Settings.
- Stores your OpenAI API key in the macOS Keychain. It is never written to preferences, logs, plans, or history.
- Sends only explicit folder metadata required for planning: relative names, file type, size, and timestamps. File contents and absolute paths are not sent.
- Accepts only supported, relative-path operations: move, rename, delete, create folder, create file, and replace.
- Revalidates plans locally, detects collisions and stale files, blocks aliases, symlinks, packages, and path escapes, then simulates on a virtual filesystem.
- Uses a durable transaction journal, recovery copies for destructive changes, automatic rollback after failures, and recovery for interrupted transactions.
- Runs in the macOS sandbox and uses persistent security-scoped access only for folders you select.

SafeRun is not a background cleanup daemon. It never runs actions until you review and confirm a successful simulation.

## Requirements

- macOS 14 Sonoma or later
- An OpenAI API key for AI planning (you can still inspect the app and its local safety UI without one)
- Internet access only when you choose to generate or test an AI plan

## Install

Download the signed, notarized DMG from [GitHub Releases](https://github.com/jelwingeuan/SafeRun/releases/latest), open it, and drag SafeRun to Applications. If macOS reports that a build is unsigned, do not treat it as a public release build.

## First run

1. Enter your API key during onboarding. SafeRun saves it to Keychain.
2. Select a folder and describe the result you want.
3. Review the generated plan and its local safety warnings.
4. Run the simulation. Resolve every conflict and rerun if the folder changed.
5. Confirm execution. Use History to review, roll back, or recover a transaction.

## Build and test

```sh
swift build -Xswiftc -warnings-as-errors
swift test
Scripts/build_release.sh --unsigned
```

`--unsigned` is for local diagnostics only. It creates `dist/SafeRun-1.0.0-UNSIGNED/SafeRun-1.0.0-UNSIGNED.dmg`; it is ad-hoc signed, not notarized, and must not be distributed publicly.

For a signed release, see [the release guide](docs/RELEASING.md). The CI workflow builds and tests every push and pull request; the release workflow signs, notarizes, staples, verifies, checksums, and publishes version tags.

## Security and privacy

See [SECURITY.md](SECURITY.md) for vulnerability reporting and the in-app Privacy & Security page for the operational privacy model.

## Limits

SafeRun intentionally refuses plans that cannot be verified safely, including external volumes, network locations, alias or symlink traversal, package contents, unsupported operations, stale plans, and ambiguous name collisions. It cannot guarantee reversibility if recovery storage is unavailable or manually removed; those conditions are shown before execution.
