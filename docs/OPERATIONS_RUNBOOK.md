# CI, runner, and release operations

This runbook is the maintainer handoff for the executable evidence defined in
[`tests/contracts/ci-lanes.json`](../tests/contracts/ci-lanes.json). It does not
broaden the supported runtime matrix: production support remains q 4.1.x on
Linux x86-64, and other platforms stay unqualified until their own retained
lane evidence exists.

## Evidence lanes

| Lane | Command or workflow contract | Retained evidence |
|---|---|---|
| Licence-free | `tools/verify_static.py`, `tools/verify_python_contracts.py`, shell syntax on GitHub-hosted Linux | Combined contract log, 14 days; this is the only lane run for untrusted public forks |
| Correctness | strict normal and four-worker isolated full JSON/JUnit | Both report sets plus a stable-ID/verdict parity receipt, 14 days |
| Coverage | `tools/verify_coverage_contract.py --out-dir …` | Isolated correctness report, non-isolated detailed coverage, and reconciliation JSON, 14 days |
| Compatibility | `tools/verify_qspec_compatibility.py --out-dir …` | Pinned upstream, native, and qspec-launcher reports plus receipt, 14 days |
| Performance | `tools/verify_benchmark_regression.py` | Raw contract log naming workload/environment mismatch decisions, 14 days |
| Hostile/release | execution/shard/property/quarantine/snapshot/TTY/hostile/pilot tools | Combined fail-closed fault log, 14 days; the release workflow retains the complete audit for 90 days |
| Soak/scale | `tools/verify_soak.py` and `tools/verify_report_scale.py` nightly | Resource samples and 10k green/failure-heavy measurements, 30 days |

GitHub Actions artifacts are the archived example result for each workflow run.
The authoritative release artifact is `release-audit.json` together with its
normal, isolated, coverage, reconciliation, and auxiliary outputs. Console logs
alone are not release evidence.

## Licensed runner recovery

The self-hosted runner must carry labels `self-hosted`, `linux`, `x64`, and
`kdb`, with `q`, GNU `timeout`, `mktemp`, and Python 3 on `PATH`. Keep KX licence
material in the runner's protected filesystem or secret-management bootstrap;
never copy it into the checkout or an uploaded artifact.

If the runner is lost or quarantined:

1. Disable it in repository settings and cancel active licensed jobs.
2. Provision a clean Linux x86-64 host, install the approved q 4.1.x runtime,
   restore licence material out of band, and apply the required labels.
3. Run the prerequisite block from `.github/workflows/ci.yml`, then the
   execution matrix and a manual release workflow. Do not reuse an older audit.
4. Inspect uploaded evidence for the exact q/OS/host fields before re-enabling
   tag qualification. Rotate runner credentials after suspected compromise.

Public-fork pull requests run only the licence-free job. Licensed workflows may
run a fork only after a maintainer reviews the exact commit and moves it to a
trusted branch; self-hosted runners must not execute arbitrary fork code.

## Benchmark and soak interpretation

Pin real performance baselines to one controlled runner class. Every benchmark
record includes workload and environment fingerprints; a mismatch is
`inconclusive` unless a maintainer explicitly accepts it. Low-latency workloads
need enough raw samples to clear `benchmarkMinSamples`, and a flagged regression
must be reproduced in a second fresh q process before escalation.

The checked soak budget runs 20 in-process no-exit cycles after two warmups and
three actual watch-trigger cycles. It tracks q `used`/`heap`, symbol count and
bytes, root namespace count, IPC/Linux handles, and the timer-handler
fingerprint. On the 2026-08-14 q 4.1 Linux qualification host the observed
post-warmup growth was 3,648 used bytes and zero heap, symbol, namespace,
handle, or timer growth. The checked limits are intentionally looser operational
bounds, not a claim that q interned symbols or empty namespace names can be
reclaimed. Repeated growth above the contract requires recycling the watch
process and investigating the first divergent sample; do not raise a threshold
from one noisy run.

## External pilots and support claims

`tools/verify_external_pilots.py` exercises only the two pinned repositories
described in [EXTERNAL_PILOTS.md](EXTERNAL_PILOTS.md). Record a new pilot only
when its immutable revision, command, result, and retained artifact are present.
A passing best-effort platform or one local pilot does not edit
[COMPATIBILITY_MATRIX.md](COMPATIBILITY_MATRIX.md); support changes require a
repeatable release lane and an explicit policy update.

## Tag ownership and handoff

The release manager owns the candidate SHA, clean-clone audit, annotated tag,
remote-ref verification, release notes, and artifact-retention check. A second
maintainer verifies the audit SHA and the absence of open supported-baseline
P0/P1 defects. Signing is optional until the repository publishes a signing-key
policy; never describe an unsigned MD5 identity or manifest digest as a
signature. If signing is enabled, the release manager uses the registered Git
signing identity and the verifier checks it before the tag is pushed.

Handoff consists of the immutable candidate SHA, q/runtime/OS/runner identity,
`release-audit.json`, checksums for retained evidence, the explicitly
unqualified scope, tag/release-note text, and rollback owner. If any item is
missing, leave the candidate untagged and rerun the gate from a clean clone.
