/ diff_assertions.q - thin compat aliases onto the live musteq diff path.
/ musteqDiff/mustmatchDiff were a near-vestigial parallel rendering path; they
/ are referenced nowhere in lib/, tests/, or docs. Kept as one-line aliases (no
/ hard removal) so any out-of-tree caller keeps working. The live rich-diff
/ rendering now lives in .tst.asserts[`musteq] (dsl/assertions.q); these forward
/ to it, mapping the historical [expected;actual] arg order to musteq's
/ [actual;expected] convention.
\d .tst

musteqDiff:{[expected;actual] .tst.asserts[`musteq][actual;expected]}
mustmatchDiff: .tst.musteqDiff

\d .
