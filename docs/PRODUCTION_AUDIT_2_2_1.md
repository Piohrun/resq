# resQ 2.2.1 production audit

The sealed candidate qualification passed from a fresh clone at
`a9e0b333f0a67d8243890265090add35537e3cfb` on 2026-11-09. The run used
kdb+/q 4.1 on the supported Linux x86-64 baseline and produced schema-v1
`release-audit.json` naming that exact commit and resQ 2.2.1.

This certification commit adds the audit and compact evidence. It is run
through the same clean-clone gate before the annotated `v2.2.1` tag is created.
A document cannot contain its own Git commit without changing that commit, so
the remote annotated tag and its peeled target are the authoritative final-SHA
record.

## Result

| Contract | Evidence |
|---|---:|
| Strict suite | 799 tests; 798 pass, 1 documented skip; 2,674 assertions |
| Four-worker isolated suite | Identical 799-test semantic inventory, counts, stable IDs, and verdicts |
| Extended differential corpus | 400 loader seeds and 2,000 coverage seeds |
| Upstream qspec differential | 194 testcases over seven script-style runs (`--junit` and `--xunit`); names and verdicts match apart from five listed private-API tests |
| Total audit wall time | 690.039 seconds |
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

The release's new regression tests are part of the strict and isolated suites
above:
- the qspec surface test loads `holds` with dict, list and function `vars`,
  and an integer `maxFailRate`, alongside other expectations;
- the generator tests pin qspec's value domain under `-qspec-compat` and
  boolean-typed samples;
- the rerun workflow test runs a green suite whose state paths cannot be
  written and requires exit 0 with named warning diagnostics.

The gate also passed licence-free contracts, dependency-free Python contracts,
TTY/non-TTY behavior, preprocessing growth, supported execution modes,
distributed merging, property generation and shrinking, flake/quarantine
policy, snapshot-v2 inventory and pruning, benchmark statistics and telemetry,
hostile environments, bounded labels, normalized ingestion, two checked
external pilots, native and pinned qspec compatibility, repeated-process soak,
10k report/adapter scale budgets, empty-prefix installation, and
correctness/coverage reconciliation. Its checkout-residue check passed: the
run left no new ignored files in the candidate clone.

The measured preprocessing growth ratios were 1.968 and 1.986 for adjacent
50/100/200-expectation inputs, below the 3.0 fail-closed ceiling. Twenty
post-warm-up same-process soak cycles (including 3 watch cycles) showed zero
growth in used memory, heap, symbols, symbol bytes, namespaces, IPC handles,
and OS handles. The empty-prefix installation resolved the audited
commit, reported resQ 2.2.1, and passed all 30 quickstart tests and
61 assertions through installed launchers.

## Additional runtime evidence

Outside the release gate, kdb+/q 4.0 (KX build 2023.08.11) ran the complete
26-step gate on `f5b3402`, the last code commit before the version bump. Its
tree is identical to the candidate's apart from version strings and
documentation. Only the gate's q-version guards were relaxed, in a scratch
commit. The run reported 799 tests, 2,674 assertions and normal/isolated
parity. On q 4.1, the same code also passed the strict `-qspec-compat`
self-suite: 844 tests, 843 passed, 1 skipped. This is compatibility evidence;
q 4.0 remains outside the qualified scope below.

## Scope

Qualified: kdb+/q 4.1.x 64-bit on Linux x86-64. Unqualified and explicitly
out of scope for this audit: other q 4.x releases (q 4.0 is verified, not
release-gated), macOS, Windows, the optional AxLibraries self-coverage
provider, and unlisted external codebases and CI providers.
