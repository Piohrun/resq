# Security policy

## Reporting a vulnerability

Do not open a public issue containing exploit details, credentials, KX licence
material, or sensitive test/report data. Prefer a private GitHub security
advisory through the repository's **Security → Report a vulnerability** flow.
If private reporting is unavailable, open a minimal public issue requesting a
private maintainer contact and include no exploit or secret material.

Include affected resQ/q versions, supported-platform details, impact, minimal
reproduction steps, and whether a public workaround exists. Maintainers should
acknowledge a complete private report within seven days; remediation timing
depends on severity and safe release scope.

## Security support

The supported versions are those in [docs/SUPPORT.md](docs/SUPPORT.md). A P0
vulnerability is release-blocking. Fixes may intentionally fail closed or
disable unsafe behavior; the exception process is defined in
[docs/VERSIONING.md](docs/VERSIONING.md).

## Trust boundary

resQ executes test and loaded application q as the invoking user. `-isolate`
contains crashes, exits, hangs, and mutable q state between files; it is not a
security sandbox. Children inherit filesystem/network access, environment, and
credentials. Every concurrent worker also consumes a q runtime/licence
allocation. Never run untrusted pull-request code on a privileged self-hosted
licensed runner.

Additional boundaries:

- assertion values, exceptions, paths, stdout/stderr, snapshots, and coverage
  source can enter retained artifacts; treat them as sensitive build logs;
- statement coverage rewrites code under test and is opt-in; the differential
  corpus checks semantics but cannot prove every possible q construct;
- snapshot/update, report, discovery-scaffold, coverage, and rerun-state paths
  authorize writes chosen by the caller;
- watch mode repeatedly executes trusted source changes in one process;
- external adapters are local, stateless transforms; experimental in-process
  plugins are not a stable security boundary;
- the launcher uses exact private `0700` temporary roots and process groups, as
  documented and tested in [docs/HARDENING_AUDIT.md](docs/HARDENING_AUDIT.md).

Provision q and its licence through runner secret management. Never commit a
licence or expose it to code from an untrusted fork.
