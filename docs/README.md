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
10. [Coverage](COVERAGE.md) — Instrumenting coverage and reading LCOV output
11. [Watch mode](WATCH.md) — File-watch mode
12. [Continuous Integration](CI.md) — Production gates, artifacts, and runner prerequisites
13. [Parallel execution](PARALLEL.md) — Isolated workers and CI-level sharding
14. [Performance](PERFORMANCE.md) — Benchmarking assertions and statistics

### Migration
- [Async helpers](ASYNC.md) — Deferreds, polling helpers, and callback spies
- [Migrating from qspec](MIGRATION.md) — Compatibility boundary and adoption sequence

### Contributor / internal reference
- [Road to resQ 1.0](ROADMAP_1_0.md) — Production-readiness delivery ledger and release gates
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
| `CI.md` | Users | Production CI, coverage gates, reporter artifacts, runner setup |
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
| `internal/DESIGN_SKETCH.md` | Internal | Early API sketches (historical) |
| `internal/DISCOVERY.md` | Internal | Discovery engine design notes |
