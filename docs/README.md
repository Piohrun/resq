# resQ Documentation Index

## Suggested Reading Order

### New users
1. [Getting Started](GETTING_STARTED.md) — Installation, first test, qspec replacement, and a CI-ready baseline
2. [API Reference](API_REFERENCE.md) — Complete DSL, assertions cheat-sheet, CLI flags, and config
3. [Test Reporting](REPORTING.md) — Console output and JSON/JUnit/xUnit contracts
4. [Test observability](OBSERVABILITY.md) — Stable identity, quality signals, and ingestion
5. [External adapters](ADAPTERS.md) — NDJSON and Allure 2 transforms
6. [Ingestion contract](INGESTION.md) — Normalized joins, SQL, metric cardinality, and Grafana example
7. [Lifecycle events and plugins](EVENTS_AND_PLUGINS.md) — Ordered events, manifests, and trusted callbacks
8. [CI, runner, and release operations](OPERATIONS_RUNBOOK.md) — Evidence lanes, recovery, retention, and handoff
9. [Troubleshooting](TROUBLESHOOTING.md) — Common errors and diagnostic tips
10. [Claim-to-gate index](VERIFICATION.md) — Executable evidence behind supported correctness and performance claims

### Going deeper
11. [Fixtures](FIXTURES.md) — Fixture scopes and lifecycle hooks
12. [Snapshots](SNAPSHOTS.md) — Binary and text snapshot testing
13. [Property-based testing](PBT.md) — Generative tests with `holds`
14. [Coverage](COVERAGE.md) — Instrumenting application coverage and reading LCOV output
15. [Optional resQ self-coverage](SELF_COVERAGE.md) — Independent, partial framework evidence
16. [Watch mode](WATCH.md) — File-watch mode
17. [Continuous Integration](CI.md) — Production gates, artifacts, and runner prerequisites
18. [Compatibility matrix](COMPATIBILITY_MATRIX.md) — Supported q runtime and execution-mode parity
19. [External adoption pilots](EXTERNAL_PILOTS.md) — Pinned third-party compatibility evidence
20. [Parallel execution](PARALLEL.md) — Isolated workers, file/test/case sharding, and strict artifact merging
21. [Performance](PERFORMANCE.md) — Benchmark assertions, versioned baselines, and regression analysis

### Migration
- [Async helpers](ASYNC.md) — Deferreds, polling helpers, and callback spies
- [Migrating from qspec](MIGRATION.md) — Compatibility boundary and adoption sequence

### Contributor / internal reference
- [Road to resQ 1.0](ROADMAP_1_0.md) — Production-readiness delivery ledger and release gates
- [Post-1.0 delivery ledger](ROADMAP_POST_1_0.md) — Branch coverage, distributed execution, quality automation, and completion gates
- [Release checklist](RELEASE_CHECKLIST.md) — Executable release gate and human sign-off
- [resQ 2.0.0 release notes](RELEASE_NOTES_2_0.md) — Typed identity migration, evidence hardening, and release scope
- [resQ 2.0.0 production audit](PRODUCTION_AUDIT_2_0.md) — Clean-clone certification, scale evidence, and supported claim
- [resQ 1.8.1 release notes](RELEASE_NOTES_1_8_1.md) — Evidence-integrity hotfixes and snapshot-v2 migration
- [resQ 1.8.1 production audit](PRODUCTION_AUDIT_1_8_1.md) — Clean-clone certification and supported claim
- [resQ 1.8.0 production audit](PRODUCTION_AUDIT_1_8.md) — Superseded historical qualification evidence
- [resQ 1.8.0 release notes](RELEASE_NOTES_1_8.md) — Superseded historical release notes
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
| `VERIFICATION.md` | Users / maintainers | Claim-to-gate map for supported correctness and performance behavior |
| `API_REFERENCE.md` | Users | Full API — DSL, assertions, CLI, config |
| `REPORTING.md` | Users / CI consumers | Console, JSON, JUnit, and xUnit contracts |
| `OBSERVABILITY.md` | Users / platform teams | Stable identities and external observability ingestion |
| `ADAPTERS.md` | Platform teams | Stateless NDJSON and Allure 2 adapters |
| `INGESTION.md` | Platform teams | Normalized evidence tables, stable joins, and cardinality guidance |
| `EVENTS_AND_PLUGINS.md` | Platform teams / plugin authors | Versioned lifecycle events, execution manifests, and trusted callbacks |
| `ARCHITECTURE.md` | Contributors | Namespace layout, exit codes, file tree |
| `COVERAGE.md` | Users | Coverage instrumentation and reporting |
| `SELF_COVERAGE.md` | Maintainers | Optional independent resQ framework coverage evidence |
| `CI.md` | Users | Production CI, coverage gates, reporter artifacts, runner setup |
| `OPERATIONS_RUNBOOK.md` | Maintainers | CI evidence lanes, licensed-runner recovery, retention, and release handoff |
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
| `RELEASE_NOTES_2_0.md` | Users / maintainers | resQ 2.0.0 typed-identity migration and evidence-integrity release notes |
| `PRODUCTION_AUDIT_2_0.md` | Users / maintainers | resQ 2.0.0 clean-clone production, performance, scale, and scope evidence |
| `RELEASE_NOTES_1_8_1.md` | Users / maintainers | resQ 1.8.1 evidence-integrity fixes and migration guidance |
| `PRODUCTION_AUDIT_1_8_1.md` | Users / maintainers | resQ 1.8.1 clean-clone production evidence and limits |
| `PRODUCTION_AUDIT_1_8.md` | Users / maintainers | Superseded resQ 1.8.0 qualification evidence and limits |
| `RELEASE_NOTES_1_8.md` | Users / maintainers | Superseded resQ 1.8.0 release notes |
| `HARDENING_AUDIT.md` | Users / maintainers | Shell, path, temp, symlink, interrupt, and artifact hardening contract |
| `SUPPORT.md` | Users | Runtime/release support, issue evidence, and severity policy |
| `VERSIONING.md` | Users / maintainers | SemVer surface, schema evolution, deprecation, and releases |
| `IDENTITY.md` | Platform teams | Stable test/case identity algorithms and lifecycle |
| `internal/DESIGN_SKETCH.md` | Internal | Early API sketches (historical) |
| `internal/DISCOVERY.md` | Internal | Discovery engine design notes |
