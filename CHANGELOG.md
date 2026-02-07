# Changelog

All notable changes to the **resQ** project will be documented in this file.

## [0.2.0] - 2026-02-07 - Hardening Release

### New Features
- **Test Execution Safety**: Per-test timeouts without session kill, improved exit codes, mock restoration warnings
- **Output Robustness**: Value truncation for large outputs, XML reporter truncation
- **Enhanced Diagnostics**: Stack traces include file/suite/test context, coverage include/exclude filters (`--cov-include`, `--cov-exclude`)
- **Developer Experience**: Watch mode debouncing, `beforeAll`/`afterAll` hooks, config validation with unknown key warnings
- **Testing Patterns**: `retry` DSL for flaky tests, `testOnly` for focused testing, improved skip/pending support

### Improved
- Stack traces now show file, suite, and test context for better debugging
- Configuration validation logs warnings for unknown keys and type mismatches
- All DSL functions exposed to root and `.q` namespaces

## [0.1.0-alpha] - 2026-01-27
- Initial public release.
- Core test runner, snapshots, fixtures, mocking/spies, performance tests, coverage, discovery, and watch mode.
