# MyIDE

A minimal macOS IDE workspace built with SwiftUI and Swift Package Manager.

## What is implemented

- Session -> Window -> Pane workspace model with JSON persistence
- Functional pane types:
  - Terminal command runner
  - Code diff
  - Browser
  - Markdown preview with Mermaid support
  - Image preview
- Black-box BDD tests using Gherkin and Cucumber against the CLI boundary

## Run the app

```bash
swift run MyIDESampleMacApp
```

## Run the CLI

```bash
swift run MyIDECLI help
```

## Install the CLI

Install once to `~/.local/bin`:

```bash
./scripts/install-cli.sh
```

Install to a custom prefix:

```bash
./scripts/install-cli.sh /usr/local/bin
```

Remove the installed symlink:

```bash
./scripts/uninstall-cli.sh
```

After installation:

```bash
MyIDECLI help
```

## Run the BDD suite

```bash
npm install
npm run bdd
```

See `TESTING.md` for the automation rules. All automated tests must stay headless and must not launch a foreground app window or steal focus from the active desktop session.
