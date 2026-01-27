# Automated Test Discovery

The `resQ` Discovery Engine scans your codebase to identify untested functions and generates boilerplate test stubs automatically.

## 🌟 Capabilities

- **Dependency-Aware**: Parses function bodies to find calls to other namespaces (e.g., detecting that `.order.new` calls `.risk.check`).
- **Smart Stubs**: Generates test code that includes `.tst.mock` suggestions for identified dependencies.
- **Project Tree**: Visualizes code coverage structure in the terminal.

---

## 🚀 Usage

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
Returns `exit 1` if untested functions are found.

---

## 🛠️ How It Works

1.  **Static Analysis**: Uses `lib/static_analysis.q` to parse `.q` files.
2.  **Function Extraction**: Identifies function definitions (including multi-line).
3.  **Dependency Scanning**: Tokenizes function bodies to find external calls (e.g., `.other.func`).
4.  **Matching**: Checks if a corresponding test file exists and contains the function name.

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
