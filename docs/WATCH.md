# Watch Mode

resQ includes a powerful **Smart Watch Mode** that accelerates your development loop by automatically re-running relevant tests whenever you modify code.

## 🚀 Quick Start

Start the watcher from your project root:

```bash
q resq.q watch
```

By default, this watches the current directory (`.`) recursively.

### Watching Specific Directories

To reduce noise or focus on specific modules, pass directories as arguments:

```bash
q resq.q watch src/analytics tests/analytics
```

---

## 🧠 How It Works

The watcher uses a "Smart Reloading" heuristic to decide what to run:

1.  **Test Changed (`tests/test_foo.q`)**:
    *   The watcher identifies it as a test file.
    *   **Action**: Runs *only* that test file.
    *   *Benefit*: Instant feedback on the test you are writing.

2.  **Source Changed (`src/foo.q`)**:
    *   The watcher parses the filename to find its "base" name (`foo`).
    *   It scans for a corresponding test file (e.g., `tests/test_foo.q` or `tests/foo.q`).
    *   **Action**:
        *   If a match is found: Runs *only* that test file.
        *   If no match is found: Runs the **Full Test Suite** (safety fallback).

3.  **Config/Core Changed**:
    *   If a file doesn't match standard patterns or seems to be a core utility.
    *   **Action**: Runs the **Full Test Suite**.

---

## 🛠️ Configuration

The watcher is designed to be zero-config, but it respects your project structure.

- **File Detection**: Uses `lib/static_analysis.q` to find `.q` files, ignoring hidden files (starting with `.`).
- **Execution**: Runs tests in-process via `lib/runner.q` on each change. This keeps the loop fast while still reloading the affected test files.

---

## ⚡ Performance Tips

- **Ignore Build Artifacts**: The watcher automatically ignores hidden directories like `.git`, `.idea`, etc. Ensure your build artifacts (if any) are in hidden folders or outside the watch target.
- **Focused Watch**: If working on a massive monorepo, always specify the subdirectories you are working on (e.g., `q resq.q watch src/order tests/order`) to keep the scan loop fast.

---

## ❓ Troubleshooting

**Q: The watcher isn't picking up my new file.**
A: The watcher scans for *existing* files on startup. It re-scans directory lists periodically (every 1s). If you just created a file, give it a second. If it's in a new directory, ensure that directory is under the watched root.

**Q: It keeps running ALL tests.**
A: This means the heuristic couldn't link your source file to a specific test file. Ensure your naming convention is consistent (e.g., `src/foo.q` -> `tests/test_foo.q`).

**Q: I get "OS Error" or "find not found".**
A: The legacy `tools/watch.q` used shell commands. `resq.q watch` uses `lib/watch.q`, which is pure Kdb+ and cross-platform.
