# resQ

**resQ** is an advanced testing, benchmarking, and discovery framework for **kdb+/q**. It extends the BDD-style foundations of `qspec` with modern features required for professional CI/CD pipelines, including high-resolution performance metrics, automated test discovery, and rich JUnit formatting.

## ⚠️ Project Status

This is an **alpha** release and should be considered **highly unstable**. APIs and behaviors may change without notice.

## 🤖 AI Assistance

Parts of the codebase and documentation were created or reviewed with AI assistance.

## 🌟 Key Features

- **🚀 High-Resolution Benchmarking**: Professional stats (min, max, avg, percentiles) and ASCII histograms built-in.
- **🔍 Automated Discovery**: Scans codebase for untested functions and generates boilerplate templates automatically.
- **📊 CI/CD Integration**: Optimized JUnit XML with detailed performance metrics and build-tracking labels.
- **🛠️ Advanced Utilities**:
  - **Fixtures**: Binary, text, and directory-based data injection.
  - **Mocking/Spies**: Clean function and variable mocking with auto-restoration.
  - **Parametrized Tests**: Run tests against a table of scenarios with `.tst.forall`.
  - **Async Testing**: Robust wait-for-condition and sleep utilities.
  - **Snapshot Testing**: Binary state persistence for complex data structures.

---

## 📦 Installation

Clone the repo and put the `bin/resq` launcher on your `PATH`:

```bash
git clone https://github.com/Piohrun/resq.git ~/.local/share/resq
ln -s ~/.local/share/resq/bin/resq ~/.local/bin/resq   # adjust to taste
```

The launcher resolves its install location (symlink-safe) and exports
`RESQ_HOME` for `resq.q` to find its modules, so you can invoke `resq`
from any directory and have it operate on **your** project's `tests/`,
not the framework's. You can also set `RESQ_HOME` manually if you
prefer to call `q $RESQ_HOME/resq.q ...` directly.

---

## 🚀 Quick Start

**resQ** comes with a unified CLI for all operations.

```bash
# Run tests (from your project root, after installing the launcher)
resq test tests/

# Or invoke q directly from the resq repo
q resq.q test examples/quickstart/test

# Run with HTML coverage
q resq.q cover examples/quickstart/test

# Start Discovery Engine
q resq.q discover examples/quickstart/src examples/quickstart/test
```

---

## 🔍 Automated Test Discovery

Check your codebase for coverage gaps and generate boilerplate instantly. The discovery engine provides a visual Project Coverage Tree and an interactive workflow.

### Usage
```bash
q resq.q discover src/ tests/
```

**Features:**
- **Visual Tree**: Instantly see which directories lack tests.
- **Smart Templates**: Generates ready-to-fill `should` blocks for untested functions.
- **Namespace Aware**: Correctly identifies functions within `\d` namespace blocks.

---

## 📈 Benchmarking

Measure performance with statistical rigor using the built-in benchmark utilities.

```q
/ Simple benchmark
.tst.benchmark.hist[.tst.benchmark.measure[100; {sma[20;1000?100f]}]`time; 10];

/ Assert performance thresholds
perf["Fast SMA"; `maxTime`runs!(10; 100)]{
  sma[10;data];
};
```

```

---

## 🛡️ Robustness Features (New)

resQ now includes advanced safeguards to ensure test integrity in production:

### 🔒 Strict Mode
Prevent false positives in CI pipelines.
```bash
q resq.q test -strict my_tests/
```
If no tests are found/executed, this flag forces a **non-zero exit code**, ensuring that an empty test suite is treated as a failure.

Strict mode can also be enabled in `resq.json`:
```json
{
  "strict": true
}
```

### 📦 Namespace Isolation (Sandboxing)
Every test file is automatically loaded into a unique, isolated namespace (e.g., `.sandbox_S...`).
- **Benefit**: No need to manually cleanup local test variables.
- **Safety**: Tests cannot accidentally pollute the global namespace or affect unrelated tests.

### 🚨 Global Pollution Guard
The runner takes a snapshot of the global namespace (`.`) before and after each test.
- **Detection**: If a test leaks a global variable (e.g., `myGlobal:: 1`), resQ detects it.
- **Action**: It logs a **WARNING** and automatically deletes the leaked variable to protect subsequent tests.
- **Performance**: Set `"pollutionGuard": false` in `resq.json` to disable deep namespace snapshotting for very large sessions.

### ⚙️ Compatibility Exports
resQ exports DSL helpers in the root namespace and `.tst.*`. For legacy compatibility it can also export helpers into `.q`, but `.q` is reserved by kdb+. To disable those compatibility exports:
```json
{
  "qNamespaceExports": false
}
```

---

## 🛠️ Writing Tests

### Basic Spec
```q
.tst.desc["Math Ops"]{
  should["add numbers correctly"]{[]
    (1 + 1) musteq 2;
  };
};
```

---

## 📦 Dependencies

- **kdb+ 3.x+**
- **qspec** (core library)

## 🙏 Acknowledgements

This project is built on top of the `qspec` testing library (MIT):
https://github.com/nugend/qspec

## ⚖️ License
MIT License.
