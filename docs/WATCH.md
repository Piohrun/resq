# Watch Mode

resQ includes a **Watch Mode** that re-runs affected tests whenever source or test files change.

## Quick Start

```bash
resq watch src/ tests/
```

Pass one or more directories to watch. On each detected change, resQ re-runs the relevant tests in-process and prints the result.

---

## How It Works

### Change detection

The watcher polls the watched directories on a fixed interval. Each `.q` file
is fingerprinted by its size and high-resolution modification token; platforms
that expose only whole seconds add a fixed-width, 64 KiB-chunked content digest. Same-size edits
within one second therefore still trigger a run. Metadata remains batch-statted
in bounded chunks rather than launching one subprocess per file. New and
deleted files are detected too. Hidden files (names starting with `.`) are
ignored.

### What gets re-run

1. **Test file changed**: runs only that file.
2. **Source file changed**: looks for a matching test file using the configured discovery conventions (`src/foo.q` → `tests/test_foo.q` or `tests/foo_test.q` by default). If found, runs it. If not found, runs the full suite as a safety fallback.
3. **File deleted**: runs the full remaining suite because the deleted path cannot be targeted safely.
4. **Other file changed**: runs the full suite.

### Poll interval

Default is 1 second. Override by setting `.tst.watch.interval` (in seconds) before the watcher starts, or in a project bootstrap file.

---

## Configuration

Watch mode runs without a TTY — it works under redirected stdin and in CI environments. It uses a foreground poll loop (not `.z.ts`), so it does not interfere with any timer handler your code may define.

---

## Troubleshooting

**Q: A new file isn't being picked up.**
A: The watcher re-scans directory listings on each poll cycle, so new files are detected within one poll interval (default 1 second).

**Q: It keeps running the full suite instead of just one file.**
A: The heuristic couldn't match the changed source file to a test file. Ensure naming is consistent (`src/foo.q` → `tests/test_foo.q` or `tests/foo_test.q`).

**Q: I need to watch more directories.**
A: Pass all of them as arguments: `resq watch src/ lib/ tests/`.
