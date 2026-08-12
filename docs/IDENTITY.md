# Stable test and case identity

Machine consumers and rerun state use resQ-generated identities, not display
labels or sandbox namespaces.

## Algorithms in 1.x

`testId` is:

```text
"test_" + hex(md5(repoRelativeFile + "\n" + suite + "\n" + description))
```

`caseId` is:

```text
"case_" + hex(md5(testId + "\n" + zeroBasedCaseIndex + "\n" + qRepr(parameters)))
```

Here `qRepr` is q's canonical `.Q.s1` representation. MD5 is used only as a
compact deterministic label; these IDs are not signatures, secrets, or a
security boundary.

The algorithms are stable public contracts for resQ 1.x. Changing their inputs,
normalization, hash, prefix, or case-index rule requires a major release.

## What remains stable

A test keeps its ID across checkout roots, CI hosts, q processes, normal versus
isolated execution, worker counts, ordering seeds, shards, and line-number-only
edits. A parameter case keeps its ID when its parent identity, zero-based case
position, and parameter value/representation remain unchanged.

## What intentionally changes identity

- moving/renaming the test file relative to the invocation repository root;
- changing suite or test description;
- changing a parameter value, q type/representation, or case index;
- invoking an external test file outside the repository from a different
  absolute location (external paths remain absolute rather than fabricated).

Within one run, `(repo-relative file, suite, description)` must be unique.
Duplicate descriptions in the same suite/file deliberately collide and are not
valid observability identities; rename them before using last-failed workflows
or historical dashboards. Parameter cases likewise require deterministic order.

`run.id` identifies one invocation and must never be used for test history.
Generated sandbox `namespace` is suppressed from machine dimensions. For
dashboards use `testId`, or `(testId, caseId)` for a parameter case, and retain
the display fields only as labels.
