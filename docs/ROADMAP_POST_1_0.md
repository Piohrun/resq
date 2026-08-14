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

- [x] Produce complete/partial snapshot-reference manifests for both backends,
  including dynamic-name declarations and shard merging.
- [x] Classify referenced, missing, obsolete, and unverified snapshots without
  treating filtered, sharded, interrupted, or failed runs as complete.
- [x] Add read-only audit and CI gates plus explicit dry-run-first pruning that
  moves files to recoverable `.resq/trash` storage.
- [x] Refuse symlinks and paths outside validated snapshot roots; prove
  idempotence and hostile-path safety.

## 1.8.0 — Benchmark regression analysis

- [x] Add stable benchmark identities and versioned baselines containing raw
  samples, summaries, workload configuration, and environment fingerprints.
- [x] Compare distributions with a documented, reference-validated
  non-parametric method, multiple-comparison correction, and a separate
  practical-effect threshold.
- [x] Classify improved/stable/inconclusive/regressed; environment mismatches
  remain non-gating unless explicitly accepted.
- [x] Keep baseline updates explicit, merge shard samples without identity loss,
  and emit comparisons through console, JSON, events, and adapters.

## Final completion gate

- [x] Every item above is checked with linked executable evidence.
- [x] The complete normal/isolated/concurrent/repeated/watch/sharded matrix is
  green and produces equivalent stable verdicts.
- [x] Console, JSON, XML, LCOV, HTML, state, events, manifests, and merged
  artifacts agree on their shared totals and identities.
- [x] The qspec contract, production application corpus, external pilots,
  licence-free checks, hostile-environment audit, and supported q matrix pass.
- [x] Defaults contain no new false green, silent data loss, implicit history
  mutation, or unsafe filesystem mutation.
- [x] A clean-checkout release audit passes at the final version and the audited
  commit is pushed before the roadmap is declared complete.

## Executable evidence

The consolidated [resQ 1.8.0 production audit](PRODUCTION_AUDIT_1_8.md) records
the clean-clone result. Each milestone is independently exercised by the
following checked-in contracts; the final release gate invokes all of them:

| Milestone | Executable evidence |
|---|---|
| 1.0.1 cleanup | [strict self-suite](../tests), [static/package contracts](../tools/verify_static.py), [independent self-coverage adapter](../tools/run_self_coverage.py) |
| 1.1 events/manifests | [execution matrix](../tools/verify_execution_matrix.py), [event/plugin tests](../tests/test_events_plugins.q) |
| 1.2–1.3 deep coverage | [coverage contracts](../tests/test_coverage.q), [semantic differential](../tests/test_coverage_differential.q), [nightly hardening](../.github/workflows/nightly.yml) |
| 1.4 distributed cases | [strict shard merger matrix](../tools/verify_shard_merge.py), [declarative-case tests](../tests/test_declarative_cases.q) |
| 1.5 property protocol | [property verifier](../tools/verify_property_protocol.py), [generator tests](../tests/test_generators.q) |
| 1.6 flake policy | [quarantine verifier](../tools/verify_quarantine.py), [policy tests](../tests/test_quarantine.q) |
| 1.7 snapshot lifecycle | [snapshot verifier](../tools/verify_snapshot_inventory.py), [snapshot tests](../tests/test_snapshot.q) |
| 1.8 benchmark analysis | [benchmark verifier](../tools/verify_benchmark_regression.py), [performance tests](../tests/test_perf.q) |
| Production boundary | [hostile-environment audit](../tools/verify_hostile_env.py), [external pilots](../tools/verify_external_pilots.py), [complete release gate](../tools/verify_release_gate.py) |

## 2.0.0 — Evidence integrity and major-version identity

- [x] Replace console-rendered identity inputs with framed, typed identity v3
  and reject mixed algorithm/codec evidence before joining it.
- [x] Publish text snapshot v2, strict finite JSON evidence, normalized tables
  v2, and executable SQLite/PostgreSQL/Grafana ingestion contracts.
- [x] Bound coverage hot paths and lifecycle assembly with repeated-sample,
  soak, 10k required-scale, and recorded 100k qualification gates.
- [x] Harden isolated process classification, launcher signal cleanup,
  symlinked installs, and immutable GitHub Actions dependencies.
- [ ] Complete the clean-clone v2.0.0 release qualification, archive the exact
  evidence commit, and verify the pushed annotated tag.

## Post-2.0 ecosystem ideas — not implemented

These are roadmap ideas, not resQ capabilities or release commitments:

- No IDE/editor integration is shipped. A future adapter could expose discovery
  and execution through an editor-neutral test protocol.
- No plugin registry, package discovery, or third-party distribution ecosystem
  is shipped. The implemented feature is only the documented trusted,
  in-process observer/reporter API loaded from explicit files.
- No mutation-testing runner or service is shipped. Targeted fault-injection
  tests inside resQ's own verification corpus do not constitute a user-facing
  mutation-testing product.
