# resQ 2.2.0 production audit

The sealed candidate qualification passed from a fresh clone of `main` at
`11303c109fcae17206f467e7e1ea81703b8b917a` on 2026-10-17. The run used
kdb+/q 4.1 on the supported Linux x86-64 baseline and produced schema-v1
`release-audit.json` naming that exact commit and resQ 2.2.0.

This certification commit adds the audit and compact evidence. It is run
through the same clean-clone gate before the annotated `v2.2.0` tag is created.
A document cannot contain its own Git commit without changing that commit, so
the remote annotated tag and its peeled target are the authoritative final-SHA
record.

## Result

| Contract | Evidence |
|---|---:|
| Strict suite | 790 tests; 789 pass, 1 documented skip; 2,628 assertions |
| Four-worker isolated suite | Identical 790-test semantic inventory, counts, stable IDs, and verdicts |
| Extended differential corpus | 400 loader seeds and 2,000 coverage seeds |
| Upstream qspec differential | 194 testcases over seven script-style runs (`--junit` and `--xunit`); names and verdicts match apart from five listed private-API tests |
| Total audit wall time | 715.908 seconds |
| Release-gate steps | 26 / 26 passed |

### Checked quickstart coverage

| Contract | Evidence |
|---|---:|
| Function coverage (gate basis) | 14 / 20 |
| Measured source lines | 48 / 59 |
| Statement sites | 51 / 72 |
| Statement instrumentation completeness | 100% |
| Conditional edges | 19 / 34 |
| Branch instrumentation completeness | 100% |

The upstream qspec differential now also compares `--xunit` runs, which this
release writes in qspec's own format: pinned nugend/qspec, nugend/qutil and
asatirahul/cryptoq suites ran through unmodified upstream qspec and through
`bin/qspec` the way a CI script calls them, and every testcase had the same
suite, name and verdict in both reports, apart from the five differences
[`pilots/qspec-differential.json`](../pilots/qspec-differential.json) lists
with reasons.

The gate also passed licence-free contracts, dependency-free Python contracts,
TTY/non-TTY behavior, preprocessing growth, supported execution modes,
distributed merging, property generation and shrinking, flake/quarantine
policy, snapshot-v2 inventory and pruning, benchmark statistics and telemetry,
hostile environments, bounded labels, normalized ingestion, two checked
external pilots, native and pinned qspec compatibility, repeated-process soak,
10k report/adapter scale budgets, empty-prefix installation, and
correctness/coverage reconciliation. Its checkout-residue check passed: the
run left no new ignored files in the candidate clone.

The measured preprocessing growth ratios were 1.963 and 2.016 for adjacent
50/100/200-expectation inputs, below the 3.0 fail-closed ceiling. Twenty
post-warm-up same-process soak cycles (including 3 watch cycles) showed zero
growth in used memory, heap, symbols, symbol bytes, namespaces, IPC handles,
and OS handles. The empty-prefix installation resolved the audited
commit, reported resQ 2.2.0, and passed all 30 quickstart tests and
61 assertions through installed launchers.

## Additional runtime evidence

Outside the release gate, kdb+/q 4.0 (KX build 2023.08.11) ran the audited
commit's strict self-suite (790 tests; 789 pass, 1 skip), its strict
`-qspec-compat` self-suite (835 tests; 834 pass, 1 skip), and the upstream
qspec differential (7 runs, 194 testcases); all passed. At `a6d2b6b`, the last
code commit before the version bump, q 4.0 also passed the isolated
self-suite, execution matrix, shard merge, CLI terminal, external pilot, and
pinned qspec compatibility checks with results identical to q 4.1. This is
compatibility evidence; q 4.0 remains outside the qualified scope below.

## Scope

Qualified: kdb+/q 4.1.x 64-bit on Linux x86-64. Unqualified and explicitly
out of scope for this audit: other q 4.x releases (q 4.0 is verified, not
release-gated), macOS, Windows, the optional AxLibraries self-coverage
provider, and unlisted external codebases and CI providers.
