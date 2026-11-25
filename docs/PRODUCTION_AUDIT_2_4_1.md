# resQ 2.4.1 production audit

The sealed candidate qualification passed from a fresh clone at
`bcc5cd432f659c7895caa4d698d526f0253cf016` on 2026-11-25. The run used
kdb+/q 4.1 on the supported Linux x86-64 baseline and produced schema-v1
`release-audit.json` naming that exact commit and resQ 2.4.1.

This certification commit adds the audit and compact evidence. It is run
through the same clean-clone gate before the annotated `v2.4.1` tag is created.
A document cannot contain its own Git commit without changing that commit, so
the remote annotated tag and its peeled target are the authoritative final-SHA
record.

## Result

| Contract | Evidence |
|---|---:|
| Strict suite | 1,284 tests; 1,283 pass, 1 documented skip; 4,464 assertions |
| Four-worker isolated suite, random order (seed 5115967) | Identical 1,284-test semantic inventory, counts, stable IDs, and verdicts |
| Extended differential corpus | 400 loader seeds and 2,000 coverage seeds |
| Upstream qspec differential | 206 testcases over eight script-style runs (`--junit` and `--xunit`), including resQ's `holds` value-domain probe; names and verdicts match apart from five listed private-API tests |
| Total audit wall time | 711.578 seconds |
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

The self-suite contract now also requires these tests to pass:
- `-last-failed` running the whole selection, in process and isolated, when
  none of the earlier failures is in it;
- a multi-line string in a test file keeping its text and its brackets out of
  statement grouping, and a continued `\` command read as one command;
- `resq mutate` finding the functions after a `k)` line and those followed by
  a tab, and giving the same verdicts through the worker pool as in groups;
- `exploreFile` listing only the functions a file defines;
- an interrupt before resQ has loaded stopping q at once with one line, and
  the isolated output watch leaving no `sleep` and no loop behind.

The gate also passed licence-free contracts, dependency-free Python contracts,
TTY/non-TTY behavior, preprocessing growth, supported execution modes,
distributed merging, property generation and shrinking, flake/quarantine
policy, snapshot-v2 inventory and pruning, benchmark statistics and telemetry,
hostile environments (including INT/TERM/HUP without `setsid` and `pkill`,
now also failing on any process of a signalled run that outlives it),
bounded labels, normalized ingestion, two checked external pilots, native and
pinned qspec compatibility, repeated-process soak, 10k report/adapter scale
budgets, empty-prefix installation, and correctness/coverage reconciliation.
Its checkout-residue check passed: the run left no new ignored files in the
candidate clone.

The measured preprocessing growth ratios were 2.010 and 1.946 for adjacent
50/100/200-expectation inputs, below the 3.0 fail-closed ceiling. Twenty
post-warm-up same-process soak cycles (including 3 watch cycles) showed zero
growth in used memory, heap, symbols, symbol bytes, namespaces, IPC handles,
and OS handles. The coverage report cost 3,068 ns per entry against its
6,000 ns ceiling. The empty-prefix installation resolved the audited commit,
reported resQ 2.4.1, and passed all 30 quickstart tests and 62 assertions
through installed launchers.

## Before this candidate

Candidate `99a5fee` also passed the complete gate (26/26, 1,281 tests, 4,460
assertions). It was replaced, not tagged, after an external read-only review
of the 2.4.1 changes found three edge cases, each fixed with a test that fails
without the fix: table cells in property tests were offered only their first
shrink (`af4ddc4`); `exploreFile` followed a `system "d .x"` inside a block
(`d375c87`); and a `\` command whose continuation line closed a string it
opened made the loader read the rest of the file as a string (`ea380b5`).

## The scanner measurement behind this release

Most fixes in 2.4.1 come from comparing resQ's q-source scanners with q's own
reader (`\l` line rules, `-4!` tokens, `parse`) over 3,240 distinct q files:
resQ, TorQ, KX's tick and TAQ scripts, KX's VS Code fixtures and other code.
Nothing from that corpus was executed. After the fixes, the loader's
statements match q's on all 3,113 files q accepts in full, its masking agrees
with q's tokenizer on every statement q accepts, and the dependency graph
agrees with q on every `\l` and require literal.

## Additional runtime evidence

Outside the release gate, kdb+/q 4.0 (KX build 2023.08.11) ran the complete
26-step gate on the candidate's tree. Only the gate's q-version guards were
relaxed, in a scratch commit on top of the candidate that was not published.
The run reported 1,284 tests, 4,464 assertions and normal/isolated parity in
713.8 seconds. This is compatibility evidence; q 4.0 remains outside the
qualified scope below.

## Scope

Qualified: kdb+/q 4.1.x 64-bit on Linux x86-64. Unqualified and explicitly
out of scope for this audit: other q 4.x releases (q 4.0 is verified, not
release-gated), macOS, Windows, the optional AxLibraries self-coverage
provider, and unlisted external codebases and CI providers.
