# Security policy

## Supported versions

Only the latest released SafeRun version receives security fixes.

## Reporting a vulnerability

Please do not open a public issue for a security vulnerability. Use the repository's private security-advisory reporting flow and include:

- a clear description and impact;
- reproduction steps or a minimal proof of concept;
- the SafeRun version and macOS version; and
- any suggested mitigation.

Do not include API keys, personal file paths, or private documents. We will acknowledge valid reports and coordinate a fix before public disclosure.

## Operational security

SafeRun uses the macOS sandbox, security-scoped folder bookmarks, Keychain for API credentials, strict response validation, local path validation, and explicit confirmation before execution. It does not execute shell commands from AI output.
