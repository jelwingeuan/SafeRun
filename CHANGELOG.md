# Changelog

All notable changes to SafeRun are documented here.

## 1.0.0 — 2026-09-18

First production release.

- Replaced the prototype planner with an OpenAI Responses API planner using strict Structured Outputs.
- Added Keychain-backed API-key onboarding, model selection, connection testing, and a privacy explanation.
- Added mandatory local plan validation, virtual simulation, stale-plan detection, symlink and alias blocking, and conservative collision checks.
- Added durable recovery journals, automatic failure rollback, interrupted-transaction recovery, retention, and recovery storage reporting.
- Added sandboxed folder access, progress and cancellation, execution history, onboarding, settings, accessibility labels, and light/dark appearance support.
- Added universal packaging, Developer ID signing and notarization scripts, mounted-DMG verification, checksums, CI, and tag-based GitHub release automation.
