# resQ 1.8.0 production audit

The complete release gate passed from a fresh clone of pushed `main` at code
candidate `fd3a38035099a194773df103924840e154a5c6f1` on 2026-08-13. The run used
kdb+/q 4.1 on the supported Linux x86-64 baseline and produced a validated
`release-audit.json` naming that exact commit and resQ 1.8.0.

## Result

| Contract | Evidence |
|---|---:|
| Strict suite | 696 tests; 695 pass, 1 documented skip; 2,155 assertions |
| Four-worker isolated suite | Identical 696-test inventory, counts, stable IDs, and verdicts |
| Total audit wall time | 245.845 seconds |

### Checked quickstart coverage

<!-- QUICKSTART_COVERAGE_START -->
| Contract | Evidence |
|---|---:|
| Function coverage (gate basis) | 14 / 20 |
| Measured source lines | 48 / 59 |
| Statement sites | 51 / 72 |
| Statement instrumentation completeness | 20 / 20 eligible functions |
| Conditional edges | 19 / 34 |
| Branch instrumentation completeness | 17 / 17 eligible sites |
<!-- QUICKSTART_COVERAGE_END -->

The gate also passed the licence-free contracts, Python schema/adapter tests,
supported execution matrix, distributed merger matrix, property protocol,
flake/quarantine policy, snapshot lifecycle, benchmark regression protocol,
hostile process/filesystem environment, and both pinned external adoption
pilots.

An earlier attempt exposed an assertion-dense loader performance defect:
`tests/test_config.q` could exceed the 90-second isolated-file budget. The
token-candidate search was made bounded in commit `fd3a380`; that file then
passed isolated in 5.6 seconds and the fresh-clone normal and isolated suites
completed in 117.2 and 99.7 seconds respectively. This is why the audit is a
release gate, not a documentation exercise.

## Reproduce the evidence

Run the authoritative gate from a clean checkout:

```sh
tools/verify_release_gate.py --q q --out-dir artifacts/release-audit
```

The gate implementation is [verify_release_gate.py](../tools/verify_release_gate.py).
It validates its JSON/XML artifacts, reconciles the console, report JSON,
detailed coverage JSON, LCOV, HTML, and state inventories, and writes the exact
commit, versions, timings, suite counts, coverage counts, and step durations to
`release-audit.json`.

The certification commit adds only this audit record, the evidence links, and
the completed ledger. The same clean-checkout gate is run against the pushed
certification SHA before the roadmap is considered complete; the generated
JSON, rather than this self-referential document, is the authoritative final
commit record.

## Supported claim and limits

- Production support is kdb+/q 4.1.x on Linux x86-64 as defined in the
  [compatibility matrix](COMPATIBILITY_MATRIX.md).
- Coverage is exact for its published eligible site inventories. Unsupported
  constructs are labelled as fallbacks and completeness gates fail closed; the
  framework does not claim instruction coverage for arbitrary q bytecode.
- Optional independent framework self-coverage remains partial and non-gating;
  it does not pretend resQ can safely instrument itself with its own rewriter.
- No Git tag or GitHub release is created by this audit. Tagging remains the
  explicit human step in the [release checklist](RELEASE_CHECKLIST.md).
