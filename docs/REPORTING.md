# Test Reporting

resQ has one human reporter and three machine reporters. Choose the contract
your consumer actually needs; do not parse the colourized console presentation
in CI.

## Selecting output

```bash
resq test tests/                         # final text summary
resq test tests/ -json -outDir reports  # JSON artifact
resq test tests/ -junit -outDir reports # JUnit XML artifact
resq test tests/ -xunit -outDir reports # xUnit v2 XML artifact
resq test tests/ -junit -json -outDir reports
```

Explicit `-junit`, `-xunit`, and `-json` flags compose with one another. Once any
machine reporter is selected, the console text report is **still printed** and
the artifact is written in addition to it: the summary, per-suite failures and
the verdict come first, then the `Report written to ...` lines. A machine
reporter never silences the human channel, so a CI log always shows why a run
failed without downloading an artifact.

Loading lines, run-audit lines, isolation progress, and diagnostics also go to
stdout/stderr. Add `-quiet` when you want quieter CI logs. `-quiet` suppresses
framework loading/audit and passing-suite presentation while keeping failures
and the summary; it cannot suppress output written directly by test code or
benchmark helpers.

To silence results entirely, use the qspec-compatible `-pass`, which suppresses
every reporter -- console and file alike -- while preserving the exit status.

When no reporter flag is present, `resq.json` key `fmt` selects one default
format (`text`, `junit`, `xunit`, or `json`; legacy `console`/`xml` normalize to
`text`/`junit`). Explicit reporter flags take precedence. The qspec-compatible
`-pass` option suppresses every result reporter and loading/audit chatter while
preserving the process exit status.

## Artifact names

Paths are relative to the directory from which resQ was invoked unless `outDir`
is absolute. Missing output directories are created.

| Selection | Artifact |
|-----------|----------|
| `-junit` | `test-results.xml` |
| `-xunit` | `test-results.xml` |
| `-json` | `test-results.json` |
| `-junit -json` | `test-results.junit.xml`, `test-results.json` |
| `-xunit -json` | `test-results.xunit.xml`, `test-results.json` |
| `-junit -xunit` | `test-results.junit.xml`, `test-results.xunit.xml` |
| all three | both schema-specific XML files and `test-results.json` |

When several formats are selected, schema-specific XML names prevent JUnit and
xUnit from overwriting each other. If one reporter cannot serialize or write,
resQ still attempts the others and then fails the run. An XML serialization
failure leaves a small parseable diagnostic document when the output file can
still be written.

## Failure detail in the artifacts

A failing comparison records its one-line summary **and** the structural diff:

```
Got +`sym`px!(`a`b`c;1 2 3f) — expected +`sym`px!(`a`b`c;1 2 4f)
--- diff ---
Table content mismatch (showing first 1 mismatches):
  Row 2:
    Col px: Exp=4f Act=3f
```

Both halves reach JSON (`failures`) and the JUnit/xUnit element body, so a CI
consumer sees which row, column or index differed — not just that two values
were unequal. The XML `message` attribute keeps only the summary line, because
XML attribute-value normalization would flatten the newlines.

The console prints the summary line in its end-of-run listing: the same diff has
already streamed at failure time under a `FAILURE DIFF [suite :: test]` banner,
so repeating it would double every failure in the log.

## Console output

The text reporter is intended for diagnosis. It includes suite/test status,
timing, assertion counts, errors, and presentation-oriented diffs for mismatched
atoms, lists, dictionaries, and tables. Large values and reports are bounded to
avoid turning one failed comparison into an unbounded log.

The `FAILURE DIFF` block is emitted while an assertion runs; it is not a separate
structured field in JSON or XML. Machine reports retain the canonical assertion
or error message and the `failures` list. Keep the console log when the visual
diff is useful during incident diagnosis.

## JSON schema version 1

`test-results.json` is the most complete resQ-native report. Its stable top-level
fields are:

| Field | Meaning |
|-------|---------|
| `schemaVersion` | Currently `1` |
| `framework`, `frameworkVersion`, `fmt` | Producer identity |
| `suiteCount`, `testCount`, `assertionCount` | Aggregate work performed |
| `passCount`, `failCount`, `errorCount`, `skipCount` | Aggregate outcomes |
| `duration`, `durationSeconds` | q timespan text and numeric seconds |
| `tests` | Ordered test-result rows |

Each `tests` row contains `suite`, `description`, `status`, `message`, `time`,
`durationSeconds`, `failures`, `assertsRun`, `file`, `line`, `namespace`, and
`tags`. The public statuses are `pass`, `fail`, `error`, `skip`, and `pending`.
`message` is always a string and `failures` is always a list of strings, including
on passing rows. Missing source lines serialize as JSON null.

Two top-level sections are conditional:

- `performance` appears when performance blocks ran and records their measured
  budgets/statistics.
- `coverage` appears on coverage runs and records counts, percentage, threshold,
  gate result, and whether the gate used `functions` or measured `lines`.

Consumers should branch on `schemaVersion`, ignore unknown fields, and use the
numeric `durationSeconds` for calculations. Do not derive pass/fail from the
process log; use the process exit code and aggregate counts.

## JUnit XML

JUnit output uses suite titles for `<testsuite name>` and testcase `classname`,
so identity remains useful across checkout directories. Testcases include
`file` and `line` when known. Failures, runtime errors, skips, and pending tests
map to their corresponding JUnit elements.

For a multiline failure, the element's `message` attribute contains a one-line
summary while the full newline-preserving message remains in the element body.
This avoids XML attribute normalization flattening the diagnostic.

## xUnit v2 XML

xUnit output uses suite titles for collection names and test `type`, with
`source-file` and `source-line` when known. Because xUnit v2 has no distinct
per-test Error result, resQ maps both assertion failures and runtime errors to
`Fail`; the failure's `exception-type` distinguishes `resQ.AssertionFailure`
from `resQ.Error`.

Run IDs and timestamps are generated for each report. Do not use them as stable
test identifiers; use suite plus test name (and source location where needed).

## Size limits and sensitive data

`reportLimit` (default 50,000 characters) caps a rendered failure/error message
and can be set in `resq.json`. `reportListLimit` is also accepted and retained
for compatibility, but the current reporters do not apply a separate
list-element cap; rendered list content is bounded by `reportLimit`.

Failure output can contain actual values, expected values, error text, file
paths, and test-supplied messages. Treat CI artifacts as potentially sensitive;
avoid asserting directly on credentials or production records, and apply the
same retention/access controls as other build logs.
