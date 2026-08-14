# Release checklist

resQ 1.x releases are evidence-driven. A release candidate is acceptable only
when the repository's complete executable gate passes on a supported licensed
q runner and the issue tracker has no open P0/P1 correctness defect.

## Automated gate

Run from a clean checkout:

```sh
tools/verify_release_gate.py --q q --out-dir artifacts/release-audit
```

The command fails closed and produces `release-audit.json` plus the underlying
normal, isolated, and coverage artifacts. It verifies:

- the licence-free package, documentation, JSON schema, XML, and adapter tests;
- at least 690 self-tests and 2,100 assertions, with required correctness
  contracts present and passing;
- `.q` immutability, application-local compatibility, finalizer behavior,
  exact file-handle cleanup, and structured cleanup diagnostics;
- unique stable IDs, portable paths, retry attempts, parameter cases, and
  reproducible property seeds;
- benchmark raw-sample identity, explicit baseline lifecycle, reference-pinned
  statistics, regression/improvement policy, environment safeguards, strict
  shard recomputation, and adapter telemetry;
- full-suite normal/concurrent-isolated verdict parity;
- the supported execution/repetition/randomization/sharding matrix;
- hostile path, permission, artifact, signal, and child-reaping behavior;
- both pinned external adoption pilots, the pinned qspec compatibility lane,
  repeated-process resource budgets, and 10k report/adapter scale budgets; and
- agreement among console, result JSON, detailed coverage JSON, LCOV, HTML,
  and state totals for the complete quickstart source manifest, including
  complete function, statement, and conditional-edge denominators.

The manual/tagged GitHub release workflow runs the same command on the licensed
self-hosted runner and uploads its evidence.
Runner recovery, raw-artifact retention, signing/tag ownership, external-pilot
qualification, and maintainer handoff are defined in the
[operations runbook](OPERATIONS_RUNBOOK.md).

## Human checks

After the automated gate is green:

1. Confirm the worktree is clean and the audited commit is the intended tag.
2. Triage open issues under [the support severity policy](SUPPORT.md); a P0 or
   P1 blocks release.
3. Confirm `CHANGELOG.md`, `.resq.VERSION`, README installation examples, and
   schema/version documentation name the release consistently.
4. Inspect the one permitted self-suite skip and confirm it is the documented
   non-strict text-snapshot sequencing case (or that the supported platform
   legitimately executes it).
5. Tag only the exact audited commit and retain the uploaded audit artifact.

For a post-1.0 release, every milestone up to its version in the
[delivery ledger](ROADMAP_POST_1_0.md) is release scope. No unchecked capability
may be described as shipped; the final completion gate is closed only after its
exact pushed commit passes this checklist from a clean checkout.
