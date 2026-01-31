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

## 🚀 Quick Start

**resQ** comes with a unified CLI for all operations.

```bash
# Run tests
q resq.q -test examples/quickstart/test

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
q resq.q -strict my_tests/
```
If no tests are found/executed, this flag forces a **non-zero exit code**, ensuring that an empty test suite is treated as a failure.

### 📦 Namespace Isolation (Sandboxing)
Every test file is automatically loaded into a unique, isolated namespace (e.g., `.sandbox_S...`).
- **Benefit**: No need to manually cleanup local test variables.
- **Safety**: Tests cannot accidentally pollute the global namespace or affect unrelated tests.

### 🚨 Global Pollution Guard
The runner takes a snapshot of the global namespace (`.`) before and after each test.
- **Detection**: If a test leaks a global variable (e.g., `myGlobal:: 1`), resQ detects it.
- **Action**: It logs a **WARNING** and automatically deletes the leaked variable to protect subsequent tests.

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
