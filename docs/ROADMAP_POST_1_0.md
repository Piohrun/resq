# resQ post-1.0 delivery ledger

This ledger turns the deferred work from [Road to resQ 1.0](ROADMAP_1_0.md)
and the final 1.0 audit into releasable, independently verifiable work. The
ordering follows dependency and trust: repair the remaining 1.0 paper cuts,
publish stable events and execution manifests, deepen measurement, then add
history-driven automation.

An item is complete only when implementation, regression coverage, user
documentation, schemas/artifacts, supported execution modes, changelog, and
the release audit agree. Each checked delivery task must have its own verified
commit on `main`; no later task may be used to make an earlier unchecked task
appear complete.

## Compatibility rules

1. Existing 1.x defaults remain unchanged unless correcting a false green,
   data-loss risk, or documented defect.
2. New gates, history policies, code rewriting, and filesystem mutation are
   opt-in.
3. The 1.x `testId` and `caseId` algorithms remain unchanged.
4. Partial measurement is labelled and rejected by its corresponding gate
   unless the user explicitly accepts it.
5. Plugins, shards, retries, and contexts may not bypass the unconditional
   cleanup contract or alter an underlying test result silently.
6. Destructive maintenance commands default to audit/dry-run and validate
   their exact roots before changing files.

## 1.0.1 — Audit cleanup

- [x] Sum property-test assertions across generated cases and expose the true
  executed assertion count in console and machine reports.
- [x] Make DSL shadowing scope-aware so a local named `should` does not hide an
  enclosing constructor; retain an actionable diagnostic for ambiguous source.
- [x] Correct qspec migration and reporter-behaviour documentation drift.
- [x] Keep the oversized-lambda diagnostic covered without spending roughly a
  minute in the default suite; retain the real compiler boundary in nightly
  hardening.
- [x] Add optional self-coverage evidence for resQ without pretending its own
  load-time rewriter can safely instrument itself or weakening licence-free CI.

### 1.0.1 gate

- [x] Property assertion totals equal the sum of executed generated cases.
- [x] Every documented DSL-shaped local, including `should`, has a regression.
- [x] The default self-suite no longer pays the oversized-lambda subprocess
  cost, while nightly CI still proves the real q diagnostic.
- [x] Documentation and executable reporter behaviour agree.

## 1.1.0 — Public events and execution manifests

- [x] Publish a versioned, ordered event protocol with run/file/suite/test/
  attempt/case/coverage/benchmark/diagnostic lifecycle events.
- [x] Publish trusted in-process observer and end-of-run reporter registration
  under `.resq`, with trapped failures and explicit strict-plugin policy.
- [x] Ensure plugin return values cannot mutate verdicts and document the
  in-process trust boundary.
- [x] Produce a versioned execution manifest with stable identities,
  shardability, source provenance, and a deterministic digest.
- [x] Preserve event order and payload semantics across normal, repeated,
  isolated, concurrent, and file-sharded execution.

## 1.2.0 — Conditional and LCOV branch coverage

- [x] Add a canonical branch-site inventory with stable site identity, source
  location, edge identity, eligibility, completeness, fallback, and hits.
- [x] Instrument `$[...]`, `if[...]`, and `while[...]` without changing lazy
  evaluation, return values, errors, bindings, side effects, or random state.
- [x] Seed unloaded manifest branch sites at zero and fail closed on an empty or
  partial branch denominator.
- [x] Emit `BRDA`/`BRF`/`BRH` plus matching detailed JSON, HTML, console, state,
  and independent branch/completeness gates.
- [x] Extend fixed, generated, and nightly differential corpora across the
  supported q matrix.

## 1.3.0 — Nested lambdas and coverage contexts

- [x] Discover and instrument eligible nested-lambda statements and branches
  with whole-function semantic rollback.
- [x] Represent anonymous sites under stable enclosing-function identities
  without fabricating named LCOV functions.
- [x] Add opt-in per-test coverage contexts and optional attempt detail while
  preserving identical aggregate counts.
- [x] Keep late work unattributed, bound context cardinality/memory, and merge
  contexts deterministically across workers and shards.

## 1.4.0 — Case-level distributed execution

- [x] Add `file`, `test`, and `case` shard units while retaining file sharding
  as the default.
- [x] Add declarative parameter cases discoverable without executing test
  bodies; keep existing dynamic `parametrize`/`forall` atomic and compatible.
- [x] Add a strict artifact merger that validates revision, manifest digest,
  shard union, duplicates, missing IDs, results, coverage, contexts,
  diagnostics, snapshots, and benchmarks.
- [x] Prove the merged shard result is equivalent to the unsharded manifest and
  verdict, including empty shards, retries, fixtures, isolation, and fail-fast.

## 1.5.0 — Property generator and shrink protocol

- [x] Publish deterministic `.resq.gen` sampling and shrinking protocols while
  adapting all legacy `vars` forms.
- [x] Add bounded scalar/boundary, nullable, weighted choice, collection,
  dictionary, tuple, table, map, and filter generators without consuming q's
  global random stream or interning unbounded symbols.
- [x] Replace vector bisection with deterministic, type-aware shrink trees that
  preserve the failure signature and obey step/time/candidate limits.
- [x] Emit replay tokens, original/minimal inputs, shrink counts, and explicit
  termination reasons across console and machine reports.

## 1.6.0 — Flake classification and quarantine

- [x] Add a versioned history/quarantine model keyed by stable test identity,
  including owner, reason, evidence, issue, creation, and expiry.
- [x] Detect healthy/suspect/quarantined/expired states only after configurable
  evidence; never auto-quarantine a first failure.
- [x] Separate read-only proposals from explicit manifest updates and continue
  running quarantined tests with their underlying result visible.
- [x] Make non-blocking quarantine opt-in, restore expired entries to blocking,
  and emit state consistently to console, JSON, events, and XML properties.

## 1.7.0 — Snapshot inventory and obsolete management

- [ ] Produce complete/partial snapshot-reference manifests for both backends,
  including dynamic-name declarations and shard merging.
- [ ] Classify referenced, missing, obsolete, and unverified snapshots without
  treating filtered, sharded, interrupted, or failed runs as complete.
- [ ] Add read-only audit and CI gates plus explicit dry-run-first pruning that
  moves files to recoverable `.resq/trash` storage.
- [ ] Refuse symlinks and paths outside validated snapshot roots; prove
  idempotence and hostile-path safety.

## 1.8.0 — Benchmark regression analysis

- [ ] Add stable benchmark identities and versioned baselines containing raw
  samples, summaries, workload configuration, and environment fingerprints.
- [ ] Compare distributions with a documented, reference-validated
  non-parametric method, multiple-comparison correction, and a separate
  practical-effect threshold.
- [ ] Classify improved/stable/inconclusive/regressed; environment mismatches
  remain non-gating unless explicitly accepted.
- [ ] Keep baseline updates explicit, merge shard samples without identity loss,
  and emit comparisons through console, JSON, events, and adapters.

## Final completion gate

- [ ] Every item above is checked with linked executable evidence.
- [ ] The complete normal/isolated/concurrent/repeated/watch/sharded matrix is
  green and produces equivalent stable verdicts.
- [ ] Console, JSON, XML, LCOV, HTML, state, events, manifests, and merged
  artifacts agree on their shared totals and identities.
- [ ] The qspec contract, production application corpus, external pilots,
  licence-free checks, hostile-environment audit, and supported q matrix pass.
- [ ] Defaults contain no new false green, silent data loss, implicit history
  mutation, or unsafe filesystem mutation.
- [ ] A clean-checkout release audit passes at the final version and the audited
  commit is pushed before the roadmap is declared complete.
