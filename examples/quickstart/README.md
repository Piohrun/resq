# Quickstart Example

This directory contains a sample application demonstrating the features of `resQ`.

## Structure

*   `src/`: Application source code (services, analytics, etc.)
*   `test/`: Test specifications (unit tests, specs, performance tests)

## Running the Examples

Use the `resq` CLI from the project root to run these tests.

### 1. Run All Tests
```bash
./bin/resq test examples/quickstart/test
```

### 2. Run with Coverage
```bash
./bin/resq cover examples/quickstart/test
```
This will generate `coverage.html` in the `test-results/` directory.

### 3. Watch Mode
```bash
./bin/resq watch examples/quickstart
```
The runner will re-execute tests whenever you modify files in `src/` or `test/`.

### 4. Discovery
Check for untested functions:
```bash
./bin/resq discover examples/quickstart/src examples/quickstart/test
```