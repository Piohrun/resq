# Flake evidence and quarantine

resQ keeps observation and policy separate. A bounded local history records raw
outcomes; it can classify a test as `suspect`, but it can never quarantine one.
The reviewed quarantine manifest is the only authority that can mark a stable
`testId` as `quarantined`.

## States and evidence

Every executable test/case/property/benchmark row has `tests[].quarantine`:

- `insufficient`: fewer than `flakeEvidenceMin` observations (default 3). A
  first failure always lands here.
- `healthy`: enough observations without the configured mixed pass/failure
  evidence.
- `suspect`: at least `flakeFailureMin` failures (default 2), plus a pass or a
  late-pass retry, inside the last `flakeWindow` observations (default 20).
- `quarantined`: an active, unexpired manifest entry exists.
- `expired`: the manifest entry is past `expiresAt`; the test is blocking again.

History defaults to `.resq/flake-history.json` and is atomically replaced after
a real run. Shards suffix their history files so concurrent jobs never race.
In process-isolation mode, children remain raw execution workers: each receives
private scratch state, while the parent classifies the merged rows, decides the
run verdict, and appends exactly one observation per result. This keeps normal,
isolated, and multi-worker isolated runs on the same single-writer contract.
Malformed or unsupported history is ignored. Malformed, unsupported, or invalid
quarantine policy fails closed: the raw failure remains blocking.

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

JSON exposes per-row state plus the aggregate top-level `flake` object. The
`test.finished` lifecycle event carries the same state. JUnit testcase
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
