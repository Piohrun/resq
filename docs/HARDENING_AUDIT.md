# Hostile-environment audit

This is the v1.0 release contract for the process and filesystem boundary. The
licensed CI job executes it with `tools/verify_hostile_env.py --q q`; ordinary
q self-tests cover the lower-level helpers and error classifications.

| Boundary | Release behavior | Executable evidence |
|----------|------------------|---------------------|
| Shell quoting | Every variable path/argument passed to a POSIX shell uses `.utl.shellQuote`; argument-vector Python calls bypass the shell | checkout, q wrapper, test, report, and temp paths contain spaces, apostrophe, semicolon, dollar, and brackets |
| Framework/source loading | `.utl.loadQFile` visits the containing directory, loads only the basename, and restores cwd on success/error | direct q and launcher runs through a symlinked install whose path contains hostile characters |
| Launcher temp data | `mktemp` chooses one exact guard directory, permissions are forced to `0700`, and launcher cleanup removes only that exact path | live mode/cleanup assertions in `verify_hostile_env.py` |
| Isolation temp data | scratch is created beneath the launcher-owned private root when the launcher is used, is tracked by exact allocation, restricted to `0700`, and removed after interpretation | normal/concurrent isolation self-tests plus live permission audit |
| Symlinks | launcher resolution is symlink-safe; recursive discovery does not follow directory symlinks | hostile symlinked-install audit and the golden symlink-cycle regression |
| q selection | `QBIN` selects the parent runtime and is inherited by every isolated child | logging q-wrapper invocation count in the hostile audit |
| Interrupts/children | every isolation group traps INT/TERM/HUP/EXIT, terminates the recorded timeout process groups, waits for them, and launcher EXIT cleanup removes scratch | two unbounded q children are interrupted and proved dead; no guard/scratch survives |
| Artifact paths | relative destinations anchor to invocation cwd; metacharacter paths work; write/serialization errors fail the run | parsed JSON/JUnit/xUnit under hostile absolute and relative destinations plus a blocked-destination negative test |
| Atomic rerun state | state is written beside the target, atomically renamed, shard-suffixed for concurrent writers, and malformed state is cache-miss rather than authority | `tests/test_rerun.q` |

## Deliberate limits

- Test and module filenames may contain ordinary POSIX metacharacters and
  whitespace but not newline or NUL. q system commands and line-oriented report
  formats cannot represent those names safely; resQ does not claim support for
  them.
- `-isolate` is process-failure containment, not a security sandbox. Test code
  retains the invoking user's filesystem, network, environment, and credential
  access. Do not execute untrusted pull-request code on a privileged licensed
  runner.
- A caller that invokes `q resq.q` directly bypasses the Bash launcher's
  completion guard and interrupt-owned scratch root. It remains supported for
  embedded/noquit use, but production CI should use `bin/resq`.
- Artifact directories and rerun-state files are caller-authorized paths. resQ
  normalizes and reports them but does not restrict writes to the repository.

## Manual command

```bash
tools/verify_hostile_env.py --q q
```

The audit exits non-zero at the first failed boundary and cleans its own exact
temporary root. It never scans or recursively removes a caller-owned directory.
