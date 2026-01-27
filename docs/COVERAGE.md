# Runtime Code Coverage

resQ provides powerful **Runtime Code Coverage** tracking. Unlike static scanners, this feature instruments your code at load time to measure exactly which functions are executed during your test suite.

## 🚀 Key Features
- **Auto-Instrumentation**: No manual `.recordExecution` calls needed.
- **Dependency Aware**: Tracks execution across multiple files.
- **Path Normalization**: Correctly handles absolute/relative paths and symlinks (via logical resolution).
- **LCOV Reporting**: Generates industry-standard reports for CI/CD.

---

## 🛠️ Usage

### 1. Enable Coverage in Runner
Pass the `-cov` or `-coverage` flag to the test runner.

```bash
q resq.q -test tests/ -cov
```

### 2. Update Test Loading
To enable instrumentation, your tests (or your runner) must load source code using `.tst.loadSource` instead of `system "l ..."`. 

**Example Test File:**
```q
/ Old Way (No Coverage)
/ system "l src/user.q"

/ New Way (Supports Coverage)
$[`loadSource in key .tst; .tst.loadSource; system "l "] "src/user.q"
```

### 3. Generate Reports
The runner automatically generates `coverage.lcov` in the output directory if `-cov` is enabled.

---

## 🏢 Enterprise Integration

### Option A: The "Shim" (Recommended)
If your organization uses a custom library loader, you can manually patch it.

```q
/ bootstrap_test.q
\l lib/coverage.q
.tst.initCoverage[enlist `];

.core.origLoad: .core.load;
.core.load: {[file]
  .core.origLoad file;       / 1. Load normally
  .tst.instrumentFile file;  / 2. Instrument post-load
};
```

### Option B: Auto-Discovery & Hijacking (Advanced)
For massive legacy codebases where you don't know the loader names, use the **Loader Discovery** tool.

```q
\l lib/loader_discovery.q

/ Scan core library for functions that look like loaders
.tst.loader.autoHijack["/opt/kdb/core"];
```

This scans the directory, parses function bodies to find `system "l ..."` calls, and automatically applies a wrapper that injects instrumentation.

### Complex Paths
The library includes a logical `realpath` normalizer (`.tst.resolvePath`).
- `/opt/kdb/core/utils.q`
- `../../core/utils.q`
Both resolve to the same canonical path in the coverage report, ensuring you don't get fragmented stats.

---

## 📊 CI/CD Visualization
The generated `coverage.lcov` file works with:
- **GenHTML**: `genhtml coverage.lcov -o report/`
- **Codecov / Coveralls**: Upload directly.
- **SonarQube**: Import as generic test coverage.
