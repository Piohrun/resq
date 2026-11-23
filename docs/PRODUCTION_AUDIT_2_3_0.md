# resQ 2.3.0 production audit

The sealed candidate qualification passed from a fresh clone at
`a0dbe33f7b417e339d9cf3399fa9829fc57ce1c0` on 2026-11-23. The run used
kdb+/q 4.1 on the supported Linux x86-64 baseline and produced schema-v1
`release-audit.json` naming that exact commit and resQ 2.3.0.

This certification commit adds the audit and compact evidence. It is run
through the same clean-clone gate before the annotated `v2.3.0` tag is created.
A document cannot contain its own Git commit without changing that commit, so
the remote annotated tag and its peeled target are the authoritative final-SHA
record.

## Result

| Contract | Evidence |
|---|---:|
| Strict suite | 1,079 tests; 1,078 pass, 1 documented skip; 3,742 assertions |
| Four-worker isolated suite | Identical 1,079-test semantic inventory, counts, stable IDs, and verdicts |
| Extended differential corpus | 400 loader seeds and 2,000 coverage seeds |
| Upstream qspec differential | 206 testcases over eight script-style runs (`--junit` and `--xunit`), including resQ's `holds` value-domain probe; names and verdicts match apart from five listed private-API tests |
| Total audit wall time | 685.397 seconds |
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
- the load graph judging a loader's calls instead of its definition, and
  flagging a lambda that loads where it stands;
- watch mode's selection through the real loop;
- a mutant run counted as a kill only with proof the mutant was applied, and
  the real `resq mutate` command on a generated project;
- an empty `must` condition failing under `-strict`.

The gate also passed licence-free contracts, dependency-free Python contracts,
TTY/non-TTY behavior, preprocessing growth, supported execution modes,
distributed merging, property generation and shrinking, flake/quarantine
policy, snapshot-v2 inventory and pruning, benchmark statistics and telemetry,
hostile environments, bounded labels, normalized ingestion, two checked
external pilots, native and pinned qspec compatibility, repeated-process soak,
10k report/adapter scale budgets, empty-prefix installation, and
correctness/coverage reconciliation. Its checkout-residue check passed: the
run left no new ignored files in the candidate clone.

The measured preprocessing growth ratios were 1.970 and 2.008 for adjacent
50/100/200-expectation inputs, below the 3.0 fail-closed ceiling. Twenty
post-warm-up same-process soak cycles (including 3 watch cycles) showed zero
growth in used memory, heap, symbols, symbol bytes, namespaces, IPC handles,
and OS handles. The empty-prefix installation resolved the audited
commit, reported resQ 2.3.0, and passed all 30 quickstart tests and
61 assertions through installed launchers.

## What the gate caught before this candidate

Two earlier candidates failed the gate and were replaced, not tagged:

- The gate was run with its temp directory on a deep path. Three suites wrote
  that path into generated q source with a formatter that cuts a string to the
  console width, and failed. They are fixed in `eea1ada`.
- The first form of the `-strict` empty-condition rule applied to every
  assertion built on `must`. The pinned upstream qspec suite asserts
  `x mustlt 100` on generated lists, some of them empty, and its compatibility
  lane failed. The rule now applies to `must` itself only (`1506cb0`).

## Mutation testing of resQ's own code

`resq mutate` was run on the two modules written in this release. This is
additional evidence; it is not a release-gate step.

| Module | Mutants | Detected | Left |
|---|---:|---:|---|
| `lib/load_graph.q` | 686 | 683 | Three in code that only saves time |
| `lib/mutate.q` | 1,012 | 1,009 | Three functions that print to the console |

## Additional runtime evidence

Outside the release gate, kdb+/q 4.0 (KX build 2023.08.11) ran the complete
26-step gate on the candidate's tree. Only the gate's q-version guards were
relaxed, in a scratch commit on top of the candidate. The run reported 1,079
tests, 3,742 assertions and normal/isolated parity. On q 4.1, the candidate
also passed the strict `-qspec-compat` self-suite: 1,124 tests, 1,123 passed,
1 skipped. This is compatibility evidence; q 4.0 remains outside the qualified
scope below.

## Scope

Qualified: kdb+/q 4.1.x 64-bit on Linux x86-64. Unqualified and explicitly
out of scope for this audit: other q 4.x releases (q 4.0 is verified, not
release-gated), macOS, Windows, the optional AxLibraries self-coverage
provider, and unlisted external codebases and CI providers.
