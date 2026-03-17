# Testing Guide

## Rule

All automated tests in this repository must run headlessly.

## Required constraints

- Do not launch `MyIDESampleMacApp` as part of automated test execution.
- Do not use Accessibility-driven UI automation, CGEvent input injection, or any workflow that can steal focus from the user's desktop session.
- Prefer CLI-level, model-level, and harness-based verification that runs entirely in process.
- If a feature normally opens Finder or an `NSOpenPanel`, automated tests must use the headless selection path instead of showing real UI.

## For new tests

- Add coverage through `MyIDECLI` commands backed by headless harnesses in `MyIDECore`.
- Keep Cucumber scenarios black-box from the CLI boundary, but make the CLI implementation itself headless.
- If manual GUI verification is still useful, document it separately and do not make it part of `npm run bdd`.
