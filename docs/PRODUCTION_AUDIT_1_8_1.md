# resQ 1.8.1 production audit

The sealed candidate qualification passed from a fresh clone of pushed `main`
at `3d3f9852962fb194f9d8cf70b70da542be331b93` on 2026-08-14. The run used
kdb+/q 4.1 on the supported Linux x86-64 baseline and produced schema-v1
`release-audit.json` naming that exact commit and resQ 1.8.1.

This certification commit adds the audit and compact evidence. It is run
through the same clean-clone gate before the annotated `v1.8.1` tag is created.
A document cannot contain its own Git commit without changing that commit, so
the remote annotated tag and its peeled target are the authoritative final-SHA
record.

## Result

| Contract | Evidence |
|---|---:|
| Strict suite | 745 tests; 744 pass, 1 documented skip; 2,399 assertions |
| Four-worker isolated suite | Identical 745-test semantic inventory, counts, stable IDs, and verdicts |
| Extended differential corpus | 400 loader seeds and 2,000 coverage seeds |
| Total audit wall time | 470.076 seconds |
| Release-gate steps | 24 / 24 passed |

### Checked quickstart coverage

| Contract | Evidence |
|---|---:|
| Function coverage (gate basis) | 14 / 20 |
| Measured source lines | 48 / 59 |
| Statement sites | 51 / 72 |
| Statement instrumentation completeness | 20 / 20 eligible functions |
| Conditional edges | 19 / 34 |
| Branch instrumentation completeness | 17 / 17 eligible sites |

The gate also passed licence-free contracts, dependency-free Python contracts,
TTY/non-TTY behavior, preprocessing growth, supported execution modes,
distributed merging, property generation and shrinking, flake/quarantine
policy, snapshot-v2 inventory and pruning, benchmark statistics and telemetry,
hostile environments, bounded labels, normalized ingestion, two checked
external pilots, native and pinned qspec compatibility, repeated-process soak,
10k green and failure-heavy report budgets, empty-prefix installation, and
correctness/coverage reconciliation.

The measured preprocessing growth ratios were 1.922 and 2.127 for adjacent
50/100/200-expectation inputs, below the 3.0 fail-closed ceiling. Twenty
post-warm-up same-process soak cycles grew used memory by 3,792 bytes; heap,
symbols, symbol bytes, namespaces, IPC handles, and OS handles had zero growth.
The empty-prefix installation resolved the audited commit, reported resQ 1.8.1,
and passed all 30 quickstart tests and 61 assertions through installed
launchers.

## Correctness hotfix scope

The qualification directly closes the four release-blocking findings:

- benchmark Mann-Whitney ranks and tie correction use the sorted pooled sample
  and a reference-checked asymptotic calculation;
- text snapshots use a versioned, full-fidelity canonical payload and distrust
  legacy v1 text evidence until explicit update mode rewrites it;
- JSON integer settings are normalized deliberately, with exact decimal-string
  support for seeds beyond JSON's safe integer range;
- repeated watch coverage sessions unwind instrumentation before reinitializing.

It also includes the backward-compatible evidence and availability repairs:
merge-safe flake history, fail-open malformed caches, complete NDJSON labels,
fail-closed shard snapshot completeness, crash-safe benchmark timestamps,
same-second watch fingerprints, child-private isolation state, bounded helper
processes, and immutable enclosing-run artifact and cache destinations.

`v1.8.0` is superseded and must not be used for production decisions. The
width-independent identity-v3 change remains intentionally deferred to v2.0.0
because the current identity algorithm is a documented major-version contract.

## Evidence and reproduction

The compact candidate record is committed as
[`release-audit.json`](release-evidence/v1.8.1-candidate/release-audit.json)
with its full-archive
[`checksums.sha256`](release-evidence/v1.8.1-candidate/checksums.sha256).
The complete raw archive's SHA-256 is
`f991a5b8ac2678d0ffdd7d82ffd9f032e7d254751f689485f6fe6f0447c633ac`.

Run the authoritative gate from a clean checkout:

```sh
tools/verify_release_gate.py --q q --out-dir artifacts/release-audit
```

The gate validates its JSON/XML artifacts, reconciles normal and isolated
execution, cross-checks console, report, detailed coverage, LCOV, HTML, and
state inventories, checks tracked and ignored residue, and writes exact
versions, environment, scope, timings, counts, schemas, logs, and checksums.

## Supported claim and limits

- Production support is kdb+/q 4.1.x on Linux x86-64 as defined in the
  [compatibility matrix](COMPATIBILITY_MATRIX.md).
- Coverage is exact for its published eligible site inventories. Unsupported
  constructs are labelled as fallbacks and completeness gates fail closed.
- Optional independent framework self-coverage remains partial and non-gating.
- Other q releases, macOS, Windows, the optional AxLibraries provider, and
  unlisted external projects or CI providers remain explicitly unqualified.
- The annotated `v1.8.1` tag identifies the exact final certification commit;
  verification and release publication follow the
  [release checklist](RELEASE_CHECKLIST.md).
