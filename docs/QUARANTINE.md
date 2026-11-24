# Flake evidence and quarantine

resQ keeps observation and policy separate. A bounded local history records raw
outcomes; it can classify a test as `suspect`, but it can never quarantine one.
The reviewed quarantine manifest is the only authority that can mark a stable
`testId` as `quarantined`.

## States and evidence

Every executable test/case/property/benchmark row is classified. Actionable or
evidence-backed states are exposed as `tests[].quarantine`:

- `insufficient`: fewer than `flakeEvidenceMin` observations (default 3). A
  first failure always lands here.
- `healthy`: enough observations without the configured mixed pass/failure
  evidence.
- `suspect`: at least `flakeFailureMin` failures (default 2), plus a pass or a
  late-pass retry, inside the last `flakeWindow` observations (default 20).
- `quarantined`: an active, unexpired manifest entry exists.
- `expired`: the manifest entry is past `expiresAt`; the test is blocking again.

`insufficient` remains visible in the aggregate `flake.insufficient` count but
is omitted from individual JSON rows/events and from JUnit/xUnit property
groups. Absence is therefore the compact representation of “not enough
evidence yet,” not a policy decision.

History defaults to `.resq/flake-history.json`. The `.resq/` directory carries
its own `.gitignore`, so history and rerun caches never show up in `git status`
while `.resq/quarantine.json` stays visible for review. Each write re-reads and merges
the latest file by stable execution ID under a bounded single-writer lock, then
atomically replaces it. Each execution retains at most `flakeWindow`
observations and the file retains at most 100,000 executions in deterministic
ID order. Shards suffix their history files so concurrent jobs never race.
The lock is a directory, `<history file>.lock`, that names the process holding
it. A run that finds it held waits up to five seconds, then leaves the history
untouched and says so on the console. A lock nobody holds is taken over: its
process is gone, its PID now belongs to another process (as happens when a
container is restarted), or it is more than two minutes old.
The history is one JSON document laid out with one test to a line, so that a
run reads and rewrites only the entries of the tests it ran; the others are
carried over as the text they were. A history in any other layout, such as
one written by an earlier version or by a tool, is read whole and written
back in lines.
History, proposal, and manifest documents use state schema v2 and carry the
exact identity algorithm and canonical-value codec envelope. History is kept
per q build; the manifest is not tied to one, so the same committed manifest
applies under q 4.0 and q 4.1 (see [IDENTITY.md](IDENTITY.md)).

Filtered, rerun-selected, sharded, interrupted, fail-fast, and describe-only
runs update IDs they actually observe but never erase or age unrelated IDs.
Only a completed, unfiltered, unsharded inventory increments
`unseenCompleteRuns`, and only for the test files it looked at: every entry
records its test file, and a complete run of `tests/test_a.q` says nothing
about a test in `tests/test_b.q`. An entry is aged when its file was part of
the run and the test was not seen there, or when its file no longer exists. A
deleted or renamed identity is removed after 20 such runs. This grace period
distinguishes real deletion from temporarily partial evidence while keeping
the cache bounded. An entry written before files were recorded cannot be
placed: it is never aged, and is dropped once it has not been observed for 30
days.

The last-run state that `-last-failed` and `-failed-first` read follows the
same rule. A test that failed earlier and was not run this time stays on the
list; it leaves when it passes, when a complete run of its file no longer
contains it, or when its file is gone.

In process-isolation mode, children remain raw execution workers: each receives
an immutable private copy of the parent's rerun selection state plus private
output paths, while the parent classifies the merged rows, decides the run
verdict, and is the only durable state writer. This keeps normal, isolated, and
multi-worker isolated runs on the same single-writer contract. Malformed or
unsupported history is ignored with a structured cache diagnostic. Identity-
mismatched state is preserved in an adjacent recovery archive for explicit
migration. Malformed, unsupported, or invalid quarantine policy fails closed:
the raw failure remains blocking.

## Read-only proposals

Proposal generation is explicit and does not touch policy:

```bash
resq test tests -flake-proposals
# writes .resq/quarantine-proposals.json
```

Only currently suspect rows are proposed. Review the evidence, then preview a
manifest change:

```bash
tools/update_quarantine.py \
  --proposals .resq/quarantine-proposals.json \
  --manifest .resq/quarantine.json \
  --owner market-data-quality \
  --reason "intermittent vendor sandbox" \
  --issue Q-1234 \
  --expires 2026-09-30
```

That command is a dry run. It prints the proposed versioned manifest and makes
no change. Repeat with `--write` only after review; the tool then atomically
replaces the manifest. `--test-id` is repeatable when only selected proposals
should be accepted.

Every manifest entry requires `testId`, `owner`, `reason`, `evidence`, `issue`,
`createdAt`, and `expiresAt`. Commit the policy manifest if it is shared CI
policy; keep the observation history and proposal file as disposable artifacts.

## Verdict policy

Quarantined tests always run and always retain their underlying `pass`, `fail`,
or `error` status. By default an active quarantine still blocks the run. The
explicit `-quarantine-non-blocking` flag (or `quarantineNonBlocking:true`) lets
only active, unexpired quarantines stop contributing to the exit failure. Raw
failure counts remain unchanged, and the console says that the run passed with
quarantined failures. Expired entries and malformed policy remain blocking even
when the flag is present.

JSON exposes actionable per-row state plus the aggregate top-level `flake`
object. The `test.finished` lifecycle event carries the same state when one is
present. JUnit testcase
properties and xUnit traits use `resq.quarantine.*` names for state, ownership,
reason, evidence counters, issue, creation, and expiry.

## Options

| CLI | Configuration | Default |
|-----|---------------|---------|
| `-flake-history PATH` | `flakeHistoryFile` | `.resq/flake-history.json` |
| `-quarantine-file PATH` | `quarantineFile` | `.resq/quarantine.json` |
| `-flake-proposal-file PATH` | `flakeProposalFile` | `.resq/quarantine-proposals.json` |
| `-flake-evidence-min N` | `flakeEvidenceMin` | `3` (minimum 2) |
| `-flake-failure-min N` | `flakeFailureMin` | `2` |
| `-flake-window N` | `flakeWindow` | `20`, at least the evidence minimum |
| `-flake-proposals` | `flakeProposals` | `false` |
| `-quarantine-non-blocking` | `quarantineNonBlocking` | `false` |

Use `tools/verify_quarantine.py --q q` to exercise the complete multi-run
contract, including expiry, malformed-policy behavior, normal/isolate parity,
single-writer history, and reporter parity.
