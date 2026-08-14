# resQ 1.8.0 production audit

> **Historical only:** this audit records the original `v1.8.0` qualification,
> which was superseded after false-green and evidence-integrity defects were
> reproduced. Use the immutable `v1.8.1` audit for production decisions.

The sealed qualification basis passed from a fresh clone of pushed `main` at
`9ed7fdd2fb68f5dad354e81d33ff92522fc64e4e` on 2026-08-14. The run used
kdb+/q 4.1 on the supported Linux x86-64 baseline and produced schema-v1
`release-audit.json` naming that exact commit and resQ 1.8.0.

The certification commit adds this audit, the compact evidence record, and the
completed plan ledger. That exact commit is run through the same clean-clone
gate before `v1.8.0` is created. A document cannot contain its own Git commit
without changing that commit, so the remote annotated tag and the release's
attached `release-audit.json` are the authoritative final-SHA record.

## Result

| Contract | Evidence |
|---|---:|
| Strict suite | 716 tests; 715 pass, 1 documented skip; 2,263 assertions |
| Four-worker isolated suite | Identical 716-test semantic inventory, counts, stable IDs, and verdicts |
| Extended differential corpus | 400 loader seeds and 2,000 coverage seeds |
| Total audit wall time | 410.846 seconds |
| Release-gate steps | 24 / 24 passed |

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

The gate also passed licence-free contracts, dependency-free Python contracts,
TTY/non-TTY behavior, preprocessing growth, supported execution modes,
distributed merging, property generation and shrinking, flake/quarantine
policy, snapshots, benchmark telemetry, hostile environments, bounded labels,
normalized ingestion, two checked external pilots, native and pinned qspec
compatibility, repeated-process soak, 10k green and failure-heavy report
budgets, empty-prefix installation, and correctness/coverage reconciliation.

The measured preprocessing growth ratios were 2.128 and 2.074 for adjacent
50/100/200-expectation inputs, below the 3.0 fail-closed ceiling. Twenty
post-warm-up same-process soak cycles grew used memory by 3,648 bytes; heap,
symbols, symbol bytes, namespaces, IPC handles, and OS handles had zero growth.
The empty-prefix installation resolved the audited commit, reported resQ 1.8.0,
and passed all 30 quickstart tests and 61 assertions through installed
launchers.

Several otherwise-green attempts were correctly rejected because nested test
or terminal-verification processes wrote ignored `.resq/` state into the clean
checkout. Their state was moved into private temporary lanes. Qualification was
accepted only after the final `git status --short --ignored` was empty. This is
why the audit is a release gate rather than a documentation exercise.

## Evidence and reproduction

The compact candidate record is committed as
[`release-audit.json`](release-evidence/v1.8.0-candidate/release-audit.json)
with its full-archive [`checksums.sha256`](release-evidence/v1.8.0-candidate/checksums.sha256).
The complete raw archive, including command logs and all referenced files, is
attached to the GitHub release. Its candidate archive SHA-256 is
`69292db999423dddd664979419f09af082611a0e09c16ce7018796cd935ee3d9`.

Run the authoritative gate from a clean checkout:

```sh
tools/verify_release_gate.py --q q --out-dir artifacts/release-audit
```

The gate implementation is [verify_release_gate.py](../tools/verify_release_gate.py).
It validates its JSON/XML artifacts, reconciles normal and isolated execution,
cross-checks console, report, detailed coverage, LCOV, HTML, and state
inventories, checks tracked and ignored residue, and writes exact versions,
environment, scope, timings, counts, schemas, logs, and checksums.

## Supported claim and limits

- Production support is kdb+/q 4.1.x on Linux x86-64 as defined in the
  [compatibility matrix](COMPATIBILITY_MATRIX.md).
- Coverage is exact for its published eligible site inventories. Unsupported
  constructs are labelled as fallbacks and completeness gates fail closed; the
  framework does not claim instruction coverage for arbitrary q bytecode.
- Optional independent framework self-coverage remains partial and non-gating;
  it does not pretend resQ can safely instrument itself with its own rewriter.
- Other q releases, macOS, Windows, the optional AxLibraries provider, and
  unlisted external projects or CI providers remain explicitly unqualified.
- The annotated `v1.8.0` tag identifies the exact final certification commit;
  tag/ref verification and release publication follow the
  [release checklist](RELEASE_CHECKLIST.md).
