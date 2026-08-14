# resQ 2.0.1 production audit

The sealed candidate qualification passed from a fresh clone of `main` at
`47629f731b19071ac215cafdd0513ce2a89778ca` on 2026-08-15. The run used
kdb+/q 4.1 on the supported Linux x86-64 baseline and produced schema-v1
`release-audit.json` naming that exact commit and resQ 2.0.1.

This certification commit adds the audit and compact evidence. It is run
through the same clean-clone gate before the annotated `v2.0.1` tag is created.
A document cannot contain its own Git commit without changing that commit, so
the remote annotated tag and its peeled target are the authoritative final-SHA
record.

## Result

| Contract | Evidence |
|---|---:|
| Strict suite | 766 tests; 765 pass, 1 documented skip; 2,526 assertions |
| Four-worker isolated suite | Identical 766-test semantic inventory, counts, stable IDs, and verdicts |
| Extended differential corpus | 400 loader seeds and 2,000 coverage seeds |
| Total audit wall time | 646.804 seconds |
| Release-gate steps | 25 / 25 passed |

### Checked quickstart coverage

| Contract | Evidence |
|---|---:|
| Function coverage (gate basis) | 14 / 20 |
| Measured source lines | 48 / 59 |
| Statement sites | 51 / 72 |
| Statement instrumentation completeness | 100% |
| Conditional edges | 19 / 34 |
| Branch instrumentation completeness | 100% |

The gate also passed licence-free contracts, dependency-free Python contracts
(including the newly wired Fable findings ledger with fixed-state
`closedProbe` enforcement), the hardened formatter-boundary lexer,
identity-v3 test/case goldens plus the new precision-independent
`resq-diagnostic-id-v4` construction, coverage self-instrumentation cycles
with a wrapped recorder-path helper, TTY/non-TTY behavior, preprocessing
growth, supported execution modes, distributed merging with q-emitted
diagnostic-ID reuse, property generation and shrinking, flake/quarantine
policy, snapshot-v2 inventory and pruning, benchmark statistics and
telemetry, hostile environments, bounded labels, normalized ingestion,
transactional SQL ingestion with executed Grafana queries, two checked
external pilots, native and pinned qspec compatibility, repeated-process
soak, 10k report/adapter scale budgets, empty-prefix installation, and
correctness/coverage reconciliation.

The measured preprocessing growth ratios were 2.043 and 2.151 for adjacent
50/100/200-expectation inputs, below the 3.0 fail-closed ceiling. Twenty
post-warm-up same-process soak cycles (including three watch cycles) showed
zero growth in used memory, heap, symbols, symbol bytes, namespaces, IPC
handles, and OS handles. The empty-prefix installation resolved the audited
commit, reported resQ 2.0.1, and passed all 30 quickstart tests and 61
assertions through installed launchers.

## Scope

Qualified: kdb+/q 4.1.x 64-bit on Linux x86-64. Unqualified and explicitly
out of scope for this audit: other q 4.x releases, macOS, Windows, the
optional AxLibraries self-coverage provider, and unlisted external codebases
and CI providers.
