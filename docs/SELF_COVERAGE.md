# Optional resQ self-coverage

resQ's built-in coverage rewriter cannot safely instrument the framework that
implements that rewrite. For independent, opt-in evidence, resQ can run its
test mode under [KX Developer `.cov`](https://code.kx.com/developer/libraries/code-coverage/):

```bash
tools/run_self_coverage.py \
  --library "$AXLIBRARIES_HOME/ws/coverage.q_" \
  --output artifacts/self-coverage \
  -- test tests -strict -quiet
```

The command writes `self-coverage.json` (versioned raw rows and summary) and
`self-coverage.txt` (the provider's formatted view). It preserves the test
run's exit status and fails if the provider or artifact contract is invalid.

This evidence is deliberately **partial and non-gating**. `.cov` measures
loaded lambdas and projections selected from `.tst`, `.resq`, and `.utl`; it
does not provide a complete source-file denominator for compositions,
adverb-bound functions, or code loaded after instrumentation begins. The JSON
records `complete:false` and `gatingSupported:false`, so dashboards must not
present it as resQ's release coverage percentage.

AxLibraries and a licensed q runtime are external prerequisites. They are not
vendored, downloaded automatically, or required by the licence-free CI job.
The provider path is loaded as q code in the test process, so configure only a
trusted, locally installed AxLibraries copy.
Nightly CI runs the adapter only when the repository variable
`AXLIBRARIES_HOME` points to an installation on the licensed self-hosted runner.
Process isolation is unsupported because an in-process profiler cannot observe
the child q processes.
