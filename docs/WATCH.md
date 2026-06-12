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

The watcher polls the watched directories on a fixed interval. Each `.q` file is fingerprinted by its size and mtime; a change to either triggers a test run. Hidden files (names starting with `.`) are ignored.

### What gets re-run

1. **Test file changed**: runs only that file.
2. **Source file changed**: looks for a matching test file by name convention (`src/foo.q` → `tests/test_foo.q`). If found, runs it. If not found, runs the full suite as a safety fallback.
3. **Other file changed**: runs the full suite.

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
