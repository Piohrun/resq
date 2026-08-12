# Road to resQ 1.0

This is the delivery ledger for moving resQ from 0.4.0 to a production-ready
1.0. Work is ordered by trust: verdict integrity and source compatibility come
before new features. An item is complete only when its implementation,
regression coverage, user documentation, and machine-output contract agree.

## Production contract

resQ 1.0 must guarantee that:

1. Loading resQ does not change whether ordinary application q code parses.
2. Every recoverable execution path performs the same cleanup.
3. Coverage begins with an explicit source inventory, including unloaded files.
4. Coverage gates state their basis and reject incomplete measurement by default.
5. JSON/XML results have stable identities, portable paths, run metadata,
   retry history, and structured diagnostics.
6. Supported q versions and execution modes are continuously verified.
7. The public DSL, schemas, exit codes, and compatibility policy are versioned.

## 0.4.1 — Trust hotfix

- [ ] Add regressions for reserved-name source failures, annotation collisions,
  skipped cleanup paths, partial line gates, and unloaded coverage sources.
- [x] Make legacy `-cov-min` gate on complete function coverage rather than
  automatically preferring any available line records.
- [x] Refactor `runSpec` around one unconditional, trapped finalizer.
- [ ] Correct coverage, reporting, benchmark, and compatibility documentation.
- [x] Make CI assert the expected coverage inventory, not only a percentage.

## 0.5.0 — Safe adoption

- [x] Stop exporting the DSL through reserved `.q` during normal execution.
- [x] Bind test source through a canonical, stable `.tst.dsl` export table.
- [x] Deprecate the ineffective `qNamespaceExports` configuration.
- [x] Make expectation-line annotation collision-safe and add a kill switch.
- [x] Add a production-style application compatibility corpus.
- [x] Publish the exact public qspec compatibility boundary.

## 0.6.0 — Trustworthy coverage

- [x] Add explicit `--source`/`coverageSources` source manifests.
- [x] Seed unloaded files and functions at zero hits.
- [ ] Track file/function/statement eligibility, completeness, and fallback reasons.
- [x] Add independent function, line, and instrumentation-completeness gates.
- [x] Make partial line measurement fail closed unless explicitly allowed.
- [ ] Generate LCOV, detailed coverage JSON, annotated HTML, and state output
  from one canonical model.
- [ ] Extend loader and instrumentation differential verification.
- [ ] Document the exact function/statement measurement contract.

## 0.7.0 — Observability contract

- [ ] Introduce one canonical run/result model.
- [ ] Publish and validate JSON schema v2.
- [ ] Add run IDs, timestamps, q/resQ versions, VCS/CI context, and effective config.
- [ ] Add stable test and parameter-case identities using repository-relative paths.
- [ ] Record retry attempts and expose late passes as `pass` plus `flaky:true`.
- [ ] Emit parameter cases independently and property-test seeds/results structurally.
- [ ] Add typed diagnostics for cleanup, pollution, resources, coverage, loading,
  configuration, snapshots, retries, and reporter failures.
- [ ] Generate console, JUnit, and xUnit from the canonical model.
- [ ] Structure benchmark and snapshot lifecycle results.

## 0.8.0 — Developer workflow and scale

- [ ] Add private-PRNG seeded/randomized execution order.
- [ ] Add last-failed and failed-first execution using stable IDs.
- [ ] Add deterministic file-level native sharding and shard metadata.
- [ ] Verify watch and repeated in-process runs preserve all new contracts.
- [ ] Provide thin external observability adapters; keep in-process plugins
  experimental until their failure isolation and versioning are proven.

## 0.9.0 — Release-candidate hardening

- [ ] Test the supported q-version and execution-mode matrix.
- [ ] Add licence-free docs/schema/XML/shell/package CI.
- [ ] Run extended differential corpora nightly.
- [ ] Audit shell quoting, temp permissions, symlinks, hostile paths, interrupts,
  child termination, and artifact path handling.
- [ ] Publish support, trust-boundary, SemVer, identity, and deprecation policies.
- [ ] Complete at least two representative external-codebase pilots.

## 1.0 release gate

- [ ] `.q` is unchanged by normal resQ execution.
- [x] Production-style code using DSL-shaped locals loads unchanged.
- [x] Every recoverable `runSpec` path executes cleanup.
- [ ] No pollution/resource leak crosses a suite boundary silently.
- [ ] Function coverage contains every declared source file and unloaded modules
  reduce its percentage.
- [ ] Line gates cannot silently use a partial denominator.
- [ ] Console, JSON, LCOV, and HTML coverage totals agree.
- [ ] JSON schema v2 and stable identity are documented and validated.
- [ ] Retry, parameter, and property-test results are structured and reproducible.
- [ ] Normal, isolated, concurrent, repeated, and sharded verdicts agree.
- [x] The pinned public qspec contract and application compatibility corpus pass.
- [ ] External pilots pass and no P0/P1 correctness issue remains open.

## Post-1.0

These remain valuable but do not delay a truthful 1.0:

- `$[...]` and LCOV branch coverage;
- nested-lambda branch instrumentation;
- per-test coverage contexts;
- case-level distributed sharding;
- a public reporter/event plugin lifecycle;
- richer property generators and shrinking;
- automated flake quarantine;
- obsolete-snapshot management;
- statistically significant benchmark-regression analysis.
