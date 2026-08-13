# resQ 1.8 final review-remediation plan

**Date:** 2026-08-13
**Owners:** repository maintainers, executed initially by GPT-5 Codex
**Baseline:** `299fb3691e8f0e9ad4b788991bb885f7d6116049` (`main`)
**Sources:** `20260813_gpt5_codex_plan.md`, `20260813_opus5_plan.md`, and all three model feedback files

## Outcome

Deliver a truthful, reproducible `v1.8.0` release for trusted Linux/q environments, then leave the repository with the controls needed for internal and organization-wide adoption. The plan treats the findings as one program: every defect lands with the invariant that would have detected it, every delivery step is validated before it is committed, and the release tag is created only after the exact candidate commit passes the fresh-clone gate.

The unifying problem is that resQ already validates output form thoroughly, but several important content relationships are not pinned. The completed program must guarantee that:

- preprocessing preserves q source meaning and scales predictably;
- reports reconcile with immutable execution state;
- lifecycle telemetry records observed time rather than projected time;
- CLI behavior is deterministic across terminal modes;
- report, coverage, and shard contracts reject false-green evidence;
- documentation and operational claims are derived from reproducible checks.

## Decisions made while merging the plans

1. **The release remains `v1.8.0`.** The source declares 1.8.0 and the documentation installs 1.8.0, but the tag does not exist. Calling the remediation 1.8.1 before publishing 1.8.0 would create a second version mismatch. The annotated `v1.8.0` tag is the final repository mutation.
2. **Correctness precedes optimization.** The loader literal round-trip invariant lands before the infix-rewriter optimization.
3. **The validator precedes state cleanup.** First make contradictory evidence fail, then fix the producer and prove it passes.
4. **Use an immutable canonical run snapshot.** Opus proposed a smaller state-hygiene patch and deferred the architectural cure. The broader fix is retained because report construction, self-test contamination, and repeated per-reporter model builds share the same mutable-state root cause.
5. **Event time receives a versioned semantic contract.** Existing event-v1 `occurredAt` values are run-boundary projections. Real entity timing is event v2; old v1 artifacts remain accepted but adapters must not draw fabricated timelines from them.
6. **Full evidence remains the default compatibility path.** Compact `results` and `telemetry` profiles may omit redundant sections explicitly. Sharding and release qualification require `full`.
7. **Labels enter through bounded structured input.** Use CLI/config and one `RESQ_LABELS_JSON` object. Do not enumerate arbitrary `RESQ_LABEL_*` variables into q symbols because symbols are permanent and environment input is unbounded.
8. **Coverage and isolation stay separate.** The supported design is an isolated correctness lane and a non-isolated coverage lane with inventory/verdict reconciliation. Isolation is fault containment, not a security sandbox.
9. **Timeout granularity stays per file for 1.8.** `maxTestTime` remains observational after a test returns. Both facts must be visible in CLI help and production guidance.
10. **MD5-derived identities are deterministic labels, not cryptographic signatures.** Documentation and diagnostics must use accurate terminology.
11. **Scale claims are measured before being promised.** The feedback's 1 KB/test figure is an aspiration for compact telemetry, not a pre-declared full-report guarantee.
12. **Repository work and external qualification are distinct.** Code, tests, runbooks, evidence formats, and the locally available qualification matrix are repository deliverables. A platform or external pilot is never marked qualified without an actual run on that platform/project.

## Delivery protocol

For every numbered step below:

1. preserve unrelated worktree changes;
2. add or activate the failing regression first;
3. implement the smallest coherent change;
4. run the step-specific checks plus the relevant existing suites;
5. update this plan's status ledger and any generated evidence;
6. commit only that step with a focused message;
7. push the commit to `origin/main` before starting the next step.

No later step may weaken an earlier invariant to make its checks pass. Temporary generated artifacts must live outside the working tree or in explicitly ignored output directories.

## Status ledger

| Step | Deliverable | Status |
|---:|---|---|
| 0 | Merge and publish the final plan | complete |
| 1 | Regression corpus and deterministic benchmark harness | pending |
| 2 | Loader semantic correctness, diagnostics, and scaling | pending |
| 3 | Strict report validator and immutable canonical run snapshot | pending |
| 4 | Deterministic CLI/pass/isolation contract | pending |
| 5 | Real lifecycle time, event v2, and duration semantics | pending |
| 6 | Report profiles, payload cleanup, and scale budgets | pending |
| 7 | Safe labels, VCS/CI context, and ingestion contract | pending |
| 8 | Coverage schema and adversarial coverage validation | pending |
| 9 | Licence-free validator, merger, and adapter hardening | pending |
| 10 | qspec migration, documentation, diagnostics, and hygiene | pending |
| 11 | CI lanes, benchmark/soak evidence, and support runbooks | pending |
| 12 | Fresh-clone qualification, release evidence, and `v1.8.0` tag | pending |

## Step 1 — Preserve the review failures as executable evidence

Add compact checked fixtures and generators for:

- every DSL constructor token inside q strings, including escaped quotes/backslashes, comments, multiline statements, shadowed/qualified calls, and two constructors on one physical line;
- selected/result/manifest mismatches, timestamp/duration disagreement, unexplained error diagnostics in a green run, duplicate and incomplete shard sets, and event-v1 projected timestamps;
- empty versus active quarantine state and qspec filenames such as `qspec_test_assertions.q`;
- 50/100/200/110-expectation loader inputs, 10k-result green reports, and failure-heavy reports with bounded large diffs;
- report variants containing or omitting events, manifests, coverage contexts, property evidence, and benchmark samples.

Record machine-readable baseline metadata for loader scaling, report/JUnit bytes per test, peak conversion memory, model-build count, and self-suite inventory counts. Use relative growth thresholds everywhere; use absolute timing only in a named certified-host lane.

**Validation:** each confirmed P0/P1 defect has a failing test or negative fixture before its implementation begins; generators are deterministic under a fixed seed; the existing licence-free and q smoke suites remain green.

## Step 2 — Make source rewriting correct, diagnosable, and near-linear

### Scanner correctness

Repair `.tst.annotateExpectationLineWith` so exactly one lexical action executes per loop iteration. A constructor rewrite must not fall through and consume the next character without updating string state. Preserve trailing inline comments and confirm the second constructor on one line retains its source line.

Extend the native/resQ differential suite with a semantic property: runtime string values and stable test IDs after resQ preprocessing equal those produced by native `\l` over the same generated corpus.

### Assertion diagnostics

Route `mustlt`, `mustgt`, `mustin`, `mustnin`, `mustwithin`, and `mustdelta` through a typed assertion helper. Invalid operands remain `error`, but the user sees the operator and operand types without a framework-internal backtrace. Every `@[]`/`.[]` handler must be a function.

### Rewriter scaling

First remove the byte-identical redundant mask computation in `.tst.rewriteInfixAssertions`. Then, behind the semantic differential guard, cache only the provably invariant prefix or discover executable candidates once and rewrite safely. Do not restore the previously rejected fragile shifted-offset bookkeeping.

**Validation:** literal and same-line reproductions pass; native/resQ semantic differential passes; loader, qspec, and full self-suites pass; doubling an in-range assertion block no longer approximately quadruples time; the 110-expectation ceiling fixture meets its certified-host budget.

## Step 3 — Enforce internally consistent evidence and immutable run state

### Validator invariants

Extend `tools/validate_report.py` with mode-aware checks for:

- summary status/assertion totals versus result rows;
- unique execution IDs;
- exact selected-ID/result-ID equality for complete runs;
- explicit recognized completion reasons for truncated, fail-fast, fatal/load, timeout, empty-shard, and describe-only runs;
- agreement among `selectedTestCount`, selected IDs, manifest selection, and result cardinality;
- consistent file/unit/shard counts and selected file paths;
- non-negative run duration and agreement with parsed wall-clock endpoints within tolerance;
- attempt counts, durations, intervals, and eventual test results;
- verdict semantics for error diagnostics, with explicit non-verdict fixture evidence rather than an implicit allow-list;
- framework version, revision, manifest digest, event, test, and shard identity consistency.

Older valid report-v2 fixtures remain accepted. Current producer reports advertise a completion extension and are subject to the strict contract.

### Immutable producer state

Capture, at defined boundaries, initial run metadata, complete discovered file inventory, selected execution inventory after filters/sharding, completion state/reason, final results, diagnostics, coverage, snapshots, flake evidence, and benchmarks. Final manifest/report construction consumes this snapshot rather than mutable `.tst.app.allSpecs` or globals left by internal tests.

Move full-run/report-mutating self-tests to disposable q subprocesses where practical; use a reusable snapshot/restore helper for small unit tests and prove restoration when the fixture signals.

Freeze the core canonical model once per report operation. Attach reporter-specific diagnostics through a small derived overlay so JSON, JUnit, xUnit, and console receive the same inventory without rebuilding manifest/events/coverage per reporter.

**Validation:** every negative contract fixture is rejected; complete, truncated, load-failure, timeout, empty-shard, and merged fixtures pass; fresh normal and isolated self-runs reconcile exactly; adding reporters does not multiply model construction; normal/isolate verdict maps match.

## Step 4 — Make CLI and process behavior deterministic

Define `-pass` as suppression of resQ-generated result/report chatter, not arbitrary q runtime or application output. Then:

- invoke supported q processes with quiet startup (`-q`) in the correct option position;
- use `stdin=subprocess.DEVNULL` in non-interactive Python/release subprocesses;
- assert framework markers rather than version-specific banner emptiness;
- add pseudo-TTY and redirected-stdin checks;
- retain application/test output semantics outside `-pass`.

Surface at the CLI boundary that isolation timeout is per file, `maxTestTime` cannot preempt a hang, coverage and isolation use separate lanes, each worker consumes a q runtime/licence allocation, and isolation is not a sandbox. Classify recognizable child licence/startup failure separately from malformed child reports.

**Validation:** TTY and non-TTY gate verdicts/exit codes match; `-pass` satisfies the documented framework-output contract; CLI help, CI, parallelism, production, and security docs agree.

## Step 5 — Record truthful lifecycle time and explicit duration semantics

Preserve the already observed wall-clock values in `lib/dsl/expec.q` instead of discarding them. Add nullable `startedAt`/`finishedAt` to every test and attempt construction site in one atomic change, respecting the runner's uniform-key invariant, including skip/pending, parameterized cases, and synthetic fallback rows.

Add event schema v2 and project test/attempt/file/suite events from recorded intervals in both `lib/events.q` and the duplicate lifecycle implementation in `tools/merge_shards.py`. Sequence remains logical ordering; timestamps are not required to be globally monotonic under concurrency. Continue accepting event v1, document its timestamps as projections, and prevent Allure from fabricating v1 timelines.

Within report v2 add optional, unambiguous aliases:

- `run.wallDurationSeconds`;
- `summary.testDurationSumSeconds`.

Retain the old fields through a documented deprecation period.

**Validation:** intervals are ordered and lie within the run within tolerance; interval lengths agree with monotonic durations; sequential tests no longer share one start; isolated tests may overlap; q and Python lifecycle projectors agree; old fixtures validate without fabricated Allure times.

## Step 6 — Reduce artifact cost without weakening evidence

Remove structural duplication:

- event-v2 `manifest.published` carries digest/version/counts, not the full manifest;
- per-test events omit identity already expressed by `entityId`/`parentId`;
- JUnit/xUnit and JSON omit quarantine boilerplate when state is `insufficient`;
- empty optional XML property groups are absent.

Add schema-declared profiles:

- `full`: canonical release/shard evidence, including manifest and lifecycle events;
- `results`: run/summary/tests/diagnostics with declared omissions;
- `telemetry`: normalized bounded records for ingestion.

Default behavior stays compatible. Sharding, merging, and release qualification require `full`. Omitted sections carry explicit profile/completeness metadata and never masquerade as empty measurements. Make NDJSON bounded-memory through a direct producer or incremental conversion; if neither is dependency-free, enforce and document a measured ceiling.

Set measured CI budgets for full/results/telemetry/JUnit/Allure at 10k green tests and a failure-heavy corpus: bytes per test, peak model/serialization/conversion memory, wall time, and bounded transcript completeness.

**Validation:** manifest data is serialized once; non-quarantined cases have no quarantine boilerplate; profile/completeness schema checks pass; scale jobs meet recorded budgets without silent evidence truncation.

## Step 7 — Add safe deployment context and an ingestion contract

Add bounded `run.labels` string-to-string data through explicit CLI/config input and `RESQ_LABELS_JSON`. Enforce key syntax, reserved keys, deterministic ordering, maximum count, per-key/value limits, total size, and redaction guidance. Keep free text as character vectors and do not intern unbounded external input.

Standardize `environment`, `service`, `deploymentId`, `artifactDigest`, `cluster`, `region`, and stable host group. Support CI providers only through tested mappings; generic labels remain the fallback.

Collapse VCS discovery to one cached probe per run/model build, add a safe opt-out, and degrade cleanly outside Git or in large trees.

Publish normalized run/test/attempt/benchmark/coverage/diagnostic table contracts, stable join keys, coverage site/context joins, reference SQL, low-cardinality metric mappings, and Grafana dashboard examples. Explicitly keep run IDs, SHAs, test IDs, paths, and error strings out of Prometheus/Loki label sets.

**Validation:** hostile/oversized label inputs fail clearly without symbol growth; supported provider fixtures map deterministically; VCS executes at most once; reference ingestion examples validate against a generated fixture.

## Step 8 — Fully specify and adversarially verify coverage

Replace the report schema's bare coverage object with a versioned `$defs` contract covering enabled/empty state; line, function, statement-site, and branch-edge bases; eligibility/instrumentation/hit counts and percentages; completeness and fallbacks; files/functions/sites/edges/contexts; thresholds and gate state. Keep `{}` valid outside coverage runs and cross-check aggregates against child records.

Add native-versus-instrumented oracle fixtures for `if`, `while`, lazy `$`, anonymous statements/functions, nested conditions, comments/strings, early signals, and fallback/rewrite rejection. Assert unchanged return values/side effects, exact edge counts, no impossible hits, stable site IDs, and correct test/attempt contexts. Add mutation/fault checks so percentage alone cannot certify assertion meaning.

Add an experimental self-coverage trend lane, explicitly non-gating until stable evidence supports promotion. Reconcile isolated correctness and non-isolated coverage lanes by stable inventory, verdict, and assertion count, allowing only documented differences.

**Validation:** malformed coverage objects and aggregate contradictions fail; every supported rewrite construct passes its oracle; basis/completeness gates distinguish partial instrumentation; lane reconciliation passes.

## Step 9 — Harden the licence-free trust boundary

Split standard-library Python tests into validator, merger, NDJSON, and Allure suites. Exercise `merge_shards.py` against malformed/unreadable input; framework/schema/revision/config/manifest-digest disagreement; missing, duplicate, overlapping, out-of-range, and mixed-count shards; duplicate/missing execution IDs; file/test/case modes; run-level duplicate rules; result/attempt/performance/coverage merges; deterministic ordering; fail-fast/fatal/incomplete members; and snapshot ownership.

Test the validator's new invariants directly. Test both q and Python lifecycle equivalence through shared golden fixtures. Add adapter cases for legacy/event-v2 timing, profiles, coverage, labels, Unicode, hostile paths, and large bounded transcripts.

**Validation:** all tooling tests run without q or third-party Python dependencies; mutation or targeted fault injection proves the negative cases reach the expected checks; public-fork CI runs this lane.

## Step 10 — Close migration, documentation, diagnostics, and hygiene gaps

- Make `bin/qspec <directory>` discover `qspec_test_*.q` and other pinned upstream conventions unless the user explicitly overrides `testFilePatterns`; test discovery through the public launcher.
- Replace “100% compatible” with the pinned, versioned supported surface and document separate native/compat lanes when per-suite compatibility is unavailable.
- Generate/verify quickstart coverage prose from a checked fixture, including basis and completeness; document event v1/v2, report profiles, and wall versus summed-test duration.
- Replace cryptographic wording for deterministic MD5 identities/checks.
- Rename the quickstart's `trying to fix it` example.
- Add an optional end-of-run bounded diff rendering mode while retaining streaming diagnostics.
- Add root `coverage.json` to `.gitignore` without deleting user artifacts.
- Move flake/rerun test state into private temporary directories and assert cleanup.

**Validation:** public qspec discovery works; static documentation verification catches altered fixture-derived values; comparison errors and optional final diffs are readable; a default test/coverage run leaves no unexpected repository artifacts.

## Step 11 — Institutionalize reproducible operational evidence

Publish and exercise distinct CI contracts:

| Lane | Required evidence |
|---|---|
| licence-free | Python/schema/docs/shell/static checks on public forks |
| correctness | strict isolated full JSON/JUnit with per-file timeout |
| coverage | non-isolated basis/completeness plus correctness-lane reconciliation |
| compatibility | native and pinned qspec launcher behavior |
| performance | pinned host, adequate samples, environment matching |
| hostile/release | TTY, malformed artifacts, premature exit, signals, permissions, disk pressure, shard faults |
| soak/scale | watch cycles, 10k/failure-heavy artifacts, cleanup and namespace/resource trends |

For benchmarks, record workload/environment fingerprints, treat mismatches as inconclusive, increase samples for low-latency work, and confirm flagged regressions across processes. Historical telemetry comes from registered `perf` cases.

Run repeated watch/no-quit cycles and track symbol count, namespace count, heap, handles, and timers. Use deterministic bounded sandbox names where possible and document measured recycling thresholds; never claim interned q symbols can be reclaimed.

Add support-matrix, external-pilot, raw-artifact retention, licensed-runner recovery, signing/tag ownership, and release handoff runbooks. Record only platforms and pilots actually exercised. The repository gate must make it possible for a second maintainer to reproduce release evidence without undocumented local state.

**Validation:** every CI lane has an executable target or workflow and an archived example result; benchmark mismatches fail closed/inconclusive; soak thresholds come from recorded runs; current support claims match the evidence matrix.

## Step 12 — Qualify and publish the release

From a clean clone of the exact candidate commit, run:

1. licence-free tools, schemas, docs, shell, and static checks;
2. full strict normal and isolated q suites with exact report reconciliation;
3. loader semantic differential and preprocessing budgets;
4. TTY and non-TTY CLI matrix;
5. shard-merger adversarial matrix;
6. property, snapshot, quarantine, benchmark, hostile-path, and external-pilot gates available for the qualified scope;
7. quickstart coverage with all basis/completeness checks;
8. full report validation, event timing validation, scale budgets, and adapter conversion;
9. the documented install command from an empty directory.

Archive candidate SHA, q/OS/runtime/licence environment, gate results, schemas, checksums, and explicit unqualified scope. Update the production audit to the immutable evidence. Commit and push that evidence. Then create an annotated `v1.8.0` tag on the exact audited commit, push the tag, verify the remote ref and README clone command, and publish release notes describing corrected loader semantics and report/event compatibility.

**Validation:** the remote tag resolves to the audited SHA; a fresh clone by tag installs and passes its advertised gate; no required worktree evidence is ignored or uncommitted.

## Complete finding map

| Finding | Resolution step |
|---|---:|
| C1 loader corrupts literals; F3 same-line constructor | 1–2 |
| C2 contradictory reports; C6 self-state contamination; F5 repeated model builds | 1, 3 |
| C3 missing release tag | 12, last action |
| C4 synthetic q/Python lifecycle timestamps; C16 duration ambiguity | 1, 5 |
| C5 quadratic preprocessing | 1–2 |
| C7 TTY/banner and `-pass` contract | 1, 4 |
| C8 event/manifest payload bloat; C9 quarantine boilerplate | 1, 6 |
| C10 labels; C19 CI-provider gaps; RESQ-15 ingestion joins | 7 |
| C11 sparse Python/merger tests | 1, 9 |
| C12 coverage/isolation incompatibility | 4, 8, 11 |
| C13 per-file timeout | 4, 11; per-test process mode is a future design |
| C14 stale coverage prose | 10 |
| C15 qspec filename discovery/global compatibility | 1, 10–11 |
| C17 comparison diagnostics | 2, 10 |
| C18 coverage absent from JSON schema | 8 |
| C20 coverage artifact ignore and VCS cost | 7, 10 |
| RESQ-05 experimental self-coverage | 8, 11 |
| RESQ-09 benchmark controls | 11 |
| RESQ-10 platform/maintainer maturity | 11–12, evidence only where exercised |
| RESQ-14 watch-mode resource growth | 11 |
| worker/licence allocation and sandbox wording | 4, 11 |
| console diff placement, quickstart naming, `.resq/` residue | 10 |
| failure-heavy reports, coverage rewrite correctness, shard trust logic | 1, 6, 8–9 |

## Final definition of done

The program is complete only when every ledger row is `complete`, every step has a validation record and a pushed commit on `main`, the candidate passes the clean-clone qualification for its explicitly stated support scope, and remote `v1.8.0` identifies exactly that candidate. Findings that require unavailable external platforms or organizations remain visibly unqualified; they may not be converted into unsupported claims.
