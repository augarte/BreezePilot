# Contributing to BreezePilot

Bug fixes, accessibility improvements, documentation, and reports about AC compatibility are welcome. Please keep conversations respectful and focused on the work.

## Report a bug or request a feature

Search [existing issues](https://github.com/augarte/BreezePilot/issues) before opening a new one. For a bug, include the iOS version, AC brand and model, the steps to reproduce it, what you expected, and what happened. For widget issues, include the widget size and the number of selected units. For a feature, describe what you want to be able to do and why.

Use dummy addresses and tokens in examples and redact device identifiers, home network details, and personal information from logs and screenshots. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Submit a change

1. Fork the repo, create a branch, and follow the [local setup instructions](README.md#install-from-source).
2. Keep the change focused and follow the existing Swift and SwiftUI style. If you change a device integration, preserve the controls exposed by existing models and use sanitized fixtures for protocol examples.
3. Run the **BreezePilot** scheme’s unit and UI tests on an iPhone simulator with **⌘U**. For layout changes, check the Xcode previews and include screenshots in the pull request. For hardware or widget action changes, say which AC and iOS version you tested on a physical iPhone, or describe what still needs checking.
4. Open a pull request against `main`. Explain the user-facing change, link any relevant issue, and list the checks you ran. Use focused commits with clear summaries such as `fix(widget): refresh unavailable AC status`.

By submitting a contribution, you agree to make it available under the project’s [MIT License](LICENSE).
