# Supported runtime and execution matrix

## Runtime support for resQ 1.x

| Runtime | Platform | Status |
|---------|----------|--------|
| kdb+/q 4.1.x 64-bit | Linux x86-64 | Supported and required in CI |
| other q 4.x releases | Linux | Best effort; run the matrix with `--allow-unsupported` before adoption |
| macOS / Windows | any | Not a production support target for 1.0 |

The narrow supported line is deliberate: resQ should not promise combinations
that its release pipeline cannot execute. Platform-neutral code remains where
practical, and conditional tests may pass elsewhere, but that is compatibility
evidence rather than a support commitment.

## Execution equivalence gate

`tools/verify_execution_matrix.py` runs the same five-file corpus through:

- normal in-process execution;
- isolated sequential execution;
- isolated concurrent execution;
- seeded/randomized normal and isolated execution;
- two native file shards whose disjoint union must equal the normal run.

Every JSON document is independently validated. The gate compares stable
`testId -> status` maps, checks the reported q version, and verifies shard
metadata. Repeated-process/watch contracts have separate self-tests because
they deliberately retain one q process rather than producing a comparable
single invocation.

```bash
tools/verify_execution_matrix.py --q q
```

`tools/verify_shard_merge.py` is the deeper distributed gate. It proves
file/test/case result and assertion parity, declarative fixture cases, retry
telemetry, empty shards, isolation, exact aggregate/context coverage merging,
and fail-closed rejection of incomplete, duplicate, mixed-revision/digest,
snapshot-conflict, and benchmark-conflict artifacts:

```bash
tools/verify_shard_merge.py --q q
```

Passing `--allow-unsupported` is useful for qualification experiments; it does
not change the support table or make that runtime release-gated.
