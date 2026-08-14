# Support policy

## Supported production baseline

resQ 2.x is release-gated on 64-bit kdb+/q 4.1.x running on Linux x86-64.
Normal, isolated sequential/concurrent, randomized, repeated-process, and native
sharded modes are part of that support line. The exact executable matrix is in
[COMPATIBILITY_MATRIX.md](COMPATIBILITY_MATRIX.md).

Other q 4.x releases on Linux are best-effort: a passing local matrix is useful
qualification evidence but is not a project support commitment. macOS, Windows,
32-bit q, and container/runtime combinations not represented by the release
gate may work but are not production targets for 2.x.

The supported command boundary is `bin/resq` (or the qspec-compatible
`bin/qspec`). Direct `q resq.q` invocation is supported for interactive,
embedded, and `-noquit` use, but deliberately lacks the launcher's premature
exit and interrupt-owned scratch guarantees.

## Release support window

- The newest stable release in the current major line receives correctness and
  security fixes.
- When a new minor is released, the immediately previous minor remains eligible
  for critical correctness/security backports for 90 days. Backports must be
  low-risk and do not include new features.
- Pre-1.0 releases receive no fixes after 1.0. Their migration documentation and
  changelog remain available.
- `main` is development state, not a supported release. Production automation
  should pin an immutable tag or commit.

A fix may require moving to the newest patch/minor if it depends on broader
runner or reporter changes. KX runtime/licence support remains KX's
responsibility; resQ supports its integration boundary, not the q runtime
itself.

## What a useful report contains

Open a GitHub issue with:

- resQ version/tag and `q -q` / `.z.K` output;
- Linux distribution/architecture and invocation mode;
- the exact command and relevant `resq.json` keys with secrets removed;
- a minimal test/source reproducer, exit code, and complete console diagnostic;
- JSON v2 or coverage artifacts when safe to share.

Do not put credentials, production records, licence material, or a security
exploit in a public issue. Follow [SECURITY.md](../SECURITY.md) for vulnerabilities.

## Severity used for release decisions

- **P0:** data/credential exposure, destructive behavior outside explicit
  caller paths, or a broadly exploitable security defect.
- **P1:** false-green test/coverage gate, valid application code cannot load,
  leaked live child/process state, or widespread corrupt/missing artifacts.
- **P2:** incorrect behavior with an actionable workaround or a significant
  developer/CI regression.
- **P3:** localized diagnostics, documentation, or convenience defect.

A 2.x release requires no open P0/P1 defect with a supported-baseline reproducer.
