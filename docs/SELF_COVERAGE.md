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

The command writes `self-coverage.json` (versioned raw rows and summary),
`self-coverage.txt` (the provider's formatted view), and
`self-coverage-trend.json` (up to 100 timestamped summary points). It preserves
the test run's exit status and fails if the provider or artifact contract is
invalid. The q worker runs in a private process group with a 1,200-second
deadline by default (`--timeout-seconds` overrides it). Evidence is built in a
staging directory, so a timeout kills descendants and cannot publish a partial
replacement artifact.

The trend is experimental and explicitly records `gatingSupported:false`.
It is useful for observing direction over repeated licensed runs, but neither a
single point nor a percentage increase qualifies a release. Retain the artifact
between runs to accumulate history, or publish its points to the telemetry
backend. `--trend-limit` changes the bounded retention window (1–1000).

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
