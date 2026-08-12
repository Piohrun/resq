# Test observability

resQ's JSON schema v2 is an event-rich run artifact, not a historical database.
Ingest `test-results.json`, `coverage.json`, and LCOV into the observability
system you already operate; do not keep history inside the q test process.

## Stable dimensions

- `run.id` identifies one invocation. Use `run.startedAt`, VCS/CI context, q and
  resQ versions, host, and effective config as run dimensions.
- `run.ordering` records whether execution was randomized, the replay seed, and
  the private PRNG algorithm. It never depends on or advances q's global seed.
- `run.selection` records all/last-failed/failed-first mode, history health,
  prior failure count, cache path, and the number of tests selected.
- `run.shard` records the zero-based index/count, deterministic assignment
  algorithm, global/selected file counts, and repo-relative selected files.
- `tests[].testId` is the stable test identity. It hashes repository-relative
  file, suite, and description and therefore survives a different checkout root.
- `parameterCases[].caseId` identifies a parameter case. Use `(testId, caseId)`
  when charting a matrix case.
- `suite` and `description` are labels, not database keys. `namespace` is empty
  for generated sandboxes so path-derived runtime noise cannot fragment trends.

## Useful quality signals

| Signal | Source |
|--------|--------|
| Pass/error/skip rate and duration | `summary`, `tests[]` |
| Flake rate | `tests[].flaky`, `attemptHistory` |
| Parameter hot spots | `parameterCases[]` |
| Property reproducibility | `property.seed`, failing/shrunk inputs |
| Benchmark drift | `performance[]`, `tests[].benchmark` |
| Coverage and gate health | `coverage.json` summary/files/fallbacks/gates |
| Framework hygiene | run/test `diagnostics[]` |

Coverage dashboards must label the basis. Function coverage has a complete
manifest denominator; measured-line coverage is statement instrumentation and
must be accompanied by its instrumentation-completeness percentage. It is not
branch coverage.

## Ingestion

Validate before sending:

```bash
tools/validate_report.py reports/test-results.json
```

Then map the versioned JSON to Allure, ReportPortal, OpenTelemetry, or your data
warehouse outside q. Thin adapters should be stateless transforms: preserve
`testId`, `caseId`, attempts, diagnostics, and the coverage basis instead of
reconstructing identity from display names. The JUnit/xUnit artifacts remain
useful for CI-native test tabs, but JSON is the authoritative observability
contract.
