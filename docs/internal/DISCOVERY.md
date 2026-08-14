# Automated Test Discovery
<!-- Internal/contributor reference document. Moved from docs/ to docs/internal/. -->

The resQ discovery engine statically compares source-function names with live
test source. It writes an HTML report and can generate boilerplate stubs on
request. This is a name-presence audit, not runtime coverage.

## Capabilities

- **Dependency-Aware**: Parses function bodies to find calls to other namespaces (e.g., detecting that `.order.new` calls `.risk.check`).
- **Smart Stubs**: With `-scaffold`, generates test code that includes `.tst.mock` suggestions for identified dependencies.
- **Project Tree**: Visualizes code coverage structure in the terminal.
- **Lexically exact**: Masks q strings and line/block comments, then matches
  exact fully-qualified identifier tokens, so neither commented-out tests nor
  longer names with a shared prefix count as coverage.

---

## Usage

### Interactive Mode
Run the discovery mode to start the interactive wizard:
```bash
q resq.q discover -interactive
```
1. Enter Source Directory (e.g., `src/`).
2. Enter Test Directory (e.g., `tests/`).
3. View coverage stats.
4. Choose to generate stubs for missing tests.

### CI/CD Mode (Exit Codes)
Run in check mode to fail builds if coverage is missing:
```bash
q resq.q discover src/ tests/
```
This writes `coverage_report.html` to `outDir` (default `.`) and exits 1 when
unreferenced functions are found. Add `-scaffold` to also write stubs under
`outDir/missingTests/`:

```bash
q resq.q discover src/ tests/ -scaffold -outDir artifacts/discovery
```

---

## How It Works

1.  **Static Analysis**: Uses `lib/static_analysis.q` to parse `.q` files.
2.  **Function Extraction**: Identifies function definitions (including multi-line).
3.  **Dependency Scanning**: Tokenizes function bodies to find external calls (e.g., `.other.func`).
4.  **Matching**: Masks comments and strings in all discovered test files, then
    checks whether each function name appears as an exact identifier token.

A reference in a branch that never runs still counts. Use `resq cover` to
measure execution.

### Example Generated Stub

If `src/order.q` contains:
```q
placeOrder:{[item;qty]
  if[.risk.checkLimit[qty]; 
     .db.insert[item;qty]
  ]
};
```

The generator produces:
```q
should["work with .order.placeOrder"; {[]
  / Dependencies detected: .risk.checkLimit, .db.insert
  .tst.mock[`.risk.checkLimit; {[args] (::)}];
  .tst.mock[`.db.insert; {[args] (::)}];
  
  res: .order.placeOrder[fixture;fixture];
  res mustmatch expectedValue;
}];
```
