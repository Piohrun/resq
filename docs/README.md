# resQ Documentation Index

## Suggested Reading Order

### New users
1. [Getting Started](GETTING_STARTED.md) — Installation, first test, qspec replacement, and a CI-ready baseline
2. [API Reference](API_REFERENCE.md) — Complete DSL, assertions cheat-sheet, CLI flags, and config
3. [Test Reporting](REPORTING.md) — Console output and JSON/JUnit/xUnit contracts
4. [Test observability](OBSERVABILITY.md) — Stable identity, quality signals, and ingestion
5. [External adapters](ADAPTERS.md) — NDJSON and Allure 2 transforms
6. [Troubleshooting](TROUBLESHOOTING.md) — Common errors and diagnostic tips

### Going deeper
7. [Fixtures](FIXTURES.md) — Fixture scopes and lifecycle hooks
8. [Snapshots](SNAPSHOTS.md) — Binary and text snapshot testing
9. [Property-based testing](PBT.md) — Generative tests with `holds`
10. [Coverage](COVERAGE.md) — Instrumenting application coverage and reading LCOV output
11. [Optional resQ self-coverage](SELF_COVERAGE.md) — Independent, partial framework evidence
12. [Watch mode](WATCH.md) — File-watch mode
13. [Continuous Integration](CI.md) — Production gates, artifacts, and runner prerequisites
14. [Compatibility matrix](COMPATIBILITY_MATRIX.md) — Supported q runtime and execution-mode parity
15. [External adoption pilots](EXTERNAL_PILOTS.md) — Pinned third-party compatibility evidence
16. [Parallel execution](PARALLEL.md) — Isolated workers and CI-level sharding
17. [Performance](PERFORMANCE.md) — Benchmarking assertions and statistics

### Migration
- [Async helpers](ASYNC.md) — Deferreds, polling helpers, and callback spies
- [Migrating from qspec](MIGRATION.md) — Compatibility boundary and adoption sequence

### Contributor / internal reference
- [Road to resQ 1.0](ROADMAP_1_0.md) — Production-readiness delivery ledger and release gates
- [Post-1.0 delivery ledger](ROADMAP_POST_1_0.md) — Branch coverage, distributed execution, quality automation, and completion gates
- [Release checklist](RELEASE_CHECKLIST.md) — Executable release gate and human sign-off
- [Hostile-environment audit](HARDENING_AUDIT.md) — Process/filesystem trust-boundary evidence
- [Support policy](SUPPORT.md) — Supported versions/platforms, support window, and severity
- [Versioning policy](VERSIONING.md) — Public SemVer surface and deprecation lifecycle
- [Identity contract](IDENTITY.md) — Stable test/case algorithms and change rules
- [Security policy](../SECURITY.md) — Private reporting and execution trust boundary
- `ARCHITECTURE.md` — Namespace layout, file structure, exit codes
- `internal/DISCOVERY.md` — Discovery engine design notes
- `internal/DESIGN_SKETCH.md` — Early API sketches

---

## File Map

| File | Audience | Purpose |
|------|----------|---------|
| `GETTING_STARTED.md` | New users | Installation, first test, migration, and production adoption |
| `API_REFERENCE.md` | Users | Full API — DSL, assertions, CLI, config |
| `REPORTING.md` | Users / CI consumers | Console, JSON, JUnit, and xUnit contracts |
| `OBSERVABILITY.md` | Users / platform teams | Stable identities and external observability ingestion |
| `ADAPTERS.md` | Platform teams | Stateless NDJSON and Allure 2 adapters |
| `ARCHITECTURE.md` | Contributors | Namespace layout, exit codes, file tree |
| `COVERAGE.md` | Users | Coverage instrumentation and reporting |
| `SELF_COVERAGE.md` | Maintainers | Optional independent resQ framework coverage evidence |
| `CI.md` | Users | Production CI, coverage gates, reporter artifacts, runner setup |
| `COMPATIBILITY_MATRIX.md` | Users / maintainers | Supported q runtime and execution-mode parity gate |
| `EXTERNAL_PILOTS.md` | Users / maintainers | Pinned third-party adoption evidence and its limits |
| `FIXTURES.md` | Users | Fixture scopes and lifecycle hooks |
| `ASYNC.md` | Users | Testing callbacks and deferred results |
| `MIGRATION.md` | qspec users | Porting guide from qspec |
| `PARALLEL.md` | Users | Isolated worker concurrency and CI sharding |
| `PBT.md` | Users | Property-based testing |
| `PERFORMANCE.md` | Users | Benchmarking |
| `SNAPSHOTS.md` | Users | Binary and text snapshot testing |
| `TROUBLESHOOTING.md` | Users | Debugging, exit codes, CI/CD |
| `WATCH.md` | Users | Watch mode |
| `ROADMAP_1_0.md` | Contributors | Production-readiness delivery ledger and release gates |
| `ROADMAP_POST_1_0.md` | Contributors | Post-1.0 delivery tasks, dependencies, and release gates |
| `RELEASE_CHECKLIST.md` | Maintainers | One-command release evidence and manual sign-off |
| `HARDENING_AUDIT.md` | Users / maintainers | Shell, path, temp, symlink, interrupt, and artifact hardening contract |
| `SUPPORT.md` | Users | Runtime/release support, issue evidence, and severity policy |
| `VERSIONING.md` | Users / maintainers | SemVer surface, schema evolution, deprecation, and releases |
| `IDENTITY.md` | Platform teams | Stable test/case identity algorithms and lifecycle |
| `internal/DESIGN_SKETCH.md` | Internal | Early API sketches (historical) |
| `internal/DISCOVERY.md` | Internal | Discovery engine design notes |
