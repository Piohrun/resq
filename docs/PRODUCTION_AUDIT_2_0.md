# resQ 2.0.0 production audit

The sealed candidate qualification passed from a fresh clone of pushed `main`
at `b00faa679c624410179b40f1dbae72b593879c36` on 2026-08-14. The run used
kdb+/q 4.1 release 2026.05.01 on the supported Linux x86-64 baseline and
produced schema-v1 `release-audit.json` naming that exact commit and resQ 2.0.0.

This certification commit adds the audit and compact evidence. It is run
through the same clean-clone gate before the annotated `v2.0.0` tag is created.
A document cannot contain its own Git commit without changing that commit, so
the remote annotated tag and its peeled target are the authoritative final-SHA
record.

## Result

| Contract | Evidence |
|---|---:|
| Strict suite | 765 tests; 764 pass, 1 documented skip; 2,523 assertions |
| Four-worker isolated suite | Identical semantic inventory, counts, stable IDs, and verdicts |
| Extended differential corpus | 400 loader seeds and 2,000 coverage seeds |
| Finding ledger | 44 / 44 closed; 0 open |
| Total audit wall time | 691.907 seconds |
| Release-gate steps | 25 / 25 passed |

The normal and isolated manifests both use `resq-test-case-id-v3` and the
`resq-value-v1+q-ipc-leaves` codec envelope. Their exact 765-test inventory
digest is `2756857a9db0ab2946148a08176184a8fd51c58ea8c01306adb338496ba04cb6`.

### Checked quickstart coverage

| Contract | Evidence |
|---|---:|
| Function coverage (gate basis) | 14 / 20 |
| Measured source lines | 48 / 59 |
| Statement sites | 51 / 72 |
| Statement instrumentation completeness | 100% |
| Conditional edges | 19 / 34 |
| Branch instrumentation completeness | 100% |

The gate also passed licence-free and dependency-free contracts, TTY behavior,
preprocessing linearity, supported execution modes, distributed merging,
property replay/shrinking, flake and quarantine policy, snapshot inventory,
benchmark statistics, hostile environments, bounded labels, normalized SQL
ingestion and dashboard queries, two external pilots, native and pinned qspec
compatibility, empty-prefix installation, and correctness/coverage
reconciliation.

## Performance and scale

Adjacent 50/100/200-expectation preprocessing ratios were 2.004 and 2.151,
below the 3.0 fail-closed ceiling. The calibrated medians were 4.474x statement
overhead against a 5.0x ceiling, 18.560x context overhead against 25.0x, and
3,237.813 ns per report entry against 6,000 ns.

The required artifact lane generated and validated 10,000-test green and
failure-heavy full, JUnit, NDJSON, tables, and Allure evidence. The recorded
qualification lane assembled 100,000 tests and 402,204 lifecycle events in
both q and Python; sequence, benchmark timestamps, and type-order digests
matched. Twenty post-warm-up soak cycles recorded zero growth in used/heap
memory, symbols, symbol bytes, namespaces, IPC handles, and OS handles.

The empty-prefix installation resolved the audited commit, reported resQ 2.0.0,
exercised all three externally symlinked launchers, and passed 30 quickstart
tests with 61 assertions.

## Evidence and reproduction

The compact candidate record is committed as
[`release-audit.json`](release-evidence/v2.0.0-candidate/release-audit.json)
with its full-archive
[`checksums.sha256`](release-evidence/v2.0.0-candidate/checksums.sha256).
The complete raw archive is 983,561 bytes and has SHA-256
`79cb72abb467e5635acdf371510874dcd29b8dff80b5f8de2b6e1853d85200bd`.

Run the authoritative gate from a clean checkout:

```sh
tools/verify_release_gate.py --q q --out-dir artifacts/release-audit
```

The gate validates report JSON/XML, reconciles normal, isolated, and coverage
execution, checks source and ignored checkout residue, and archives versions,
environment, qualified and unqualified scope, timings, counts, schemas, raw
logs, and SHA-256 checksums. The licensed runtime was available, but no licence
credential material was archived.

## Supported claim and limits

- Production support is kdb+/q 4.1.x on Linux x86-64 as defined in the
  [compatibility matrix](COMPATIBILITY_MATRIX.md).
- Coverage is exact for its published eligible inventories; fallback and
  completeness status remain explicit and fail closed at configured gates.
- PostgreSQL ingestion has a checked dialect/CI contract; this local audit
  executed the dependency-free SQLite reference-query and dashboard path.
- Other q releases, macOS, Windows, the optional AxLibraries provider, and
  unlisted external projects or CI providers remain explicitly unqualified.
- The annotated `v2.0.0` tag identifies the exact final certification commit;
  publication follows the [release checklist](RELEASE_CHECKLIST.md).
