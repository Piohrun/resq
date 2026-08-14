# qspec compatibility contract

Contract version: **1**

Upstream baseline: qspec commit
`9b846b68a8d808e472ba504d18c325b14b468087`

resQ is a mostly source-compatible replacement for qspec's public test DSL,
not a strict superset of every qspec API or output. This document is the
normative boundary. [MIGRATION.md](MIGRATION.md) explains how to adopt it and
gives detailed examples of semantic differences.

## Guaranteed source surface

When invoked through `bin/qspec` (or `resq test -qspec-compat`), resQ supports:

- `.tst.desc` / `describe`, `.tst.should` / `should` / `it`;
- `before`, `after`, and `alt`, including late hook declaration;
- `mock` with automatic restoration;
- `fixture` and `fixtureAs` for file, text, splayed, and directory fixtures;
- `holds` and opt-in `perf` blocks;
- qspec's 14 public assertions with the same names and arities: `must`,
  `musteq`, `mustne`, `mustmatch`, `mustnmatch`, `mustlt`, `mustgt`,
  `mustlike`, `mustin`, `mustnin`, `mustwithin`, `mustdelta`, `mustthrow`, and
  `mustnotthrow`;
- runner options `-desc` / `-describe`, `-xunit`, `-junit`, `-perf` /
  `-performance`, `-exclude`, `-only`, `-pass`, `-noquit`,
  `-fuzz-display-limt` / `-fdl`, `-ff` / `-fail-fast`, and
  `-fh` / `-fail-hard`.

The executable gate runs seven byte-identical upstream public suites: assertions,
UI, mocking, fuzzing, file fixtures, directory fixtures, and text fixtures.
`bin/qspec <directory>` also recognizes the pinned upstream `qspec_test_*.q`
filename convention in addition to resQ's normal defaults. An explicit
`testFilePatterns` configuration replaces those launcher defaults.
The unmodified legacy fuzz generator consumes q's process-global random stream,
so the compatibility harness loads a checked seed fixture before the corpus.
This makes the evidence replayable without editing upstream source; ordinary
`qspec` users do not receive an implicit global random seed.

Compatibility is certified against the pinned contract above, not as a claim
about every historical private qspec helper or output byte. Where one suite
cannot serve both semantics, CI should keep two explicit lanes: run the legacy
source through `bin/qspec` for the pinned compatibility contract, and run
native resQ suites through `bin/resq test` for strict whole-value comparisons.

## Intentional semantic differences

`bin/qspec` restores qspec's elementwise `musteq` (`=`) and `mustne` (`<>`).
Native resQ uses whole-value `~` and `not ~`. Even compatibility mode remains
fail-closed for qspec false positives: `must` rejects null and non-numeric /
non-boolean conditions, including accidentally swapped message/condition
arguments. These differences can make an invalid legacy green test fail; they
do not require a DSL rewrite.

## Explicit exclusions

The following are outside contract version 1:

- nested `desc` blocks (use `alt{}` or separate suites);
- qspec reporter callbacks and byte-for-byte console output;
- qspec private runner APIs such as `.tst.runExpec`, `.tst.getExpec`, and
  `.tst.contextHelper`;
- identical discovery-helper return types;
- identical namespace/file-path side effects after a suite;
- qspec's internal runner tests and undocumented implementation symbols.

Machine consumers must use resQ's documented JSON, JUnit, or xUnit contracts;
parsing qspec console text is not supported.

## Change policy

The public boundary is versioned independently from implementation internals.
A removal or incompatible semantic change to a guaranteed item requires a
  major resQ release. Additive aliases or features do not broaden this qspec
contract automatically. An upstream qspec-baseline change requires updating
the pinned fixtures, this document, and the executable compatibility tests in
one commit.
