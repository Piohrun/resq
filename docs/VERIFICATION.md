# Claim-to-gate index

This is the claim-to-gate index for every correctness and performance
capability resQ publishes as supported. A passing row means the named behavior
is executable on the supported q 4.1.x/Linux x86-64 release runner; it is not a
claim about unqualified runtimes, platforms, third-party projects, IDEs,
registries, or hosted services. The complete release decision is still the
fresh-clone gate in the [release checklist](RELEASE_CHECKLIST.md).

The narrowest owning tests are listed below. The aggregate release gate retains
their logs and artifacts, but it is not used as a substitute for a focused
regression.

| Claim family | Supported statement | Executable evidence |
|---|---|---|
| Core test semantics | DSL assertions, fixtures, cleanup, strict mode, retries, and runner verdicts fail closed. | [full q suite](../tests), [fixture lifecycle tests](../tests/fixture_tests) |
| qspec boundary | The published qspec surface passes both native and launcher lanes; private internals and byte-identical console output are excluded. | [qspec verifier](../tools/verify_qspec_compatibility.py), [compatibility tests](../tests/test_qspec_compat.q) |
| Process isolation | Hangs, exits, signals, child failures, cleanup, worker ordering, and timeout causes remain explicit without orphaned children. | [isolation tests](../tests/test_isolate.q), [hostile-environment verifier](../tools/verify_hostile_env.py) |
| Execution and sharding | Normal, isolated, concurrent, randomized, and file/test/case-sharded runs preserve execution identities and verdicts; the merger rejects incomplete or mixed evidence. | [execution matrix](../tools/verify_execution_matrix.py), [shard/merge verifier](../tools/verify_shard_merge.py) |
| Identity v3 | Test, case, diagnostic, and manifest identities use framed canonical bytes and are independent of console geometry; mixed algorithms/codecs do not join. | [observability identity tests](../tests/test_observability.q), [formatter boundary gate](../tools/verify_formatter_boundaries.py), [identity migration tests](../tools/tests/test_identity_migration.py) |
| Configuration | CLI, environment, and JSON settings normalize by declared field type; numeric seeds have an exact string form beyond JSON's safe integer range. | [configuration tests](../tests/test_config.q), [label/context verifier](../tools/verify_labels_context.py) |
| Snapshots | Text snapshot v2 compares full canonical values, distrusts legacy truncated text, and gates/prunes only complete safe inventories; binary snapshots remain exact. | [snapshot tests](../tests/test_snapshot.q), [inventory verifier](../tools/verify_snapshot_inventory.py) |
| Flake and quarantine state | Partial runs merge observed history without erasing unrelated evidence; malformed history fails open, policy fails closed, and aging requires complete runs. | [quarantine tests](../tests/test_quarantine.q), [quarantine verifier](../tools/verify_quarantine.py) |
| Property generation | Generator domains, private deterministic seeds, replay tokens, bounded filtering, shrinking, and failure signatures are stable and reproducible. | [generator tests](../tests/test_generators.q), [property protocol verifier](../tools/verify_property_protocol.py) |
| Benchmark statistics | Raw samples, linear-interpolated percentiles, Mann–Whitney ranks/ties, Holm correction, practical effects, environment checks, and shard recomputation follow the published method. | [performance tests](../tests/test_perf.q), [benchmark verifier](../tools/verify_benchmark_regression.py) |
| Coverage semantics | Function, measured-statement, and conditional-edge bases retain explicit completeness/fallback semantics and match native execution across the differential corpus. | [coverage tests](../tests/test_coverage.q), [coverage differential](../tests/test_coverage_differential.q), [coverage contract verifier](../tools/verify_coverage_contract.py) |
| Coverage performance | Warm probes, context accounting, report assembly, repeated initialization, and watch/coverage cycles stay within checked time and resource budgets. | [coverage performance verifier](../tools/verify_coverage_performance.py), [soak verifier](../tools/verify_soak.py) |
| Report contracts | Console, strict finite JSON, JUnit/xUnit XML, events, manifests, attempts, cases, diagnostics, snapshots, benchmarks, and coverage share one canonical run model and validated schemas. | [output tests](../tests/test_output_modules.q), [report validator](../tools/validate_report.py), [static/schema gate](../tools/verify_static.py) |
| Adapters and tables | NDJSON, Allure, report profiles, and normalized table v2 projections preserve identity, labels, host metadata, finite values, and coverage joins. | [adapter tests](../tools/tests/test_adapters.py), [ingestion tests](../tools/tests/test_ingestion.py) |
| SQL and Grafana | SQLite/PostgreSQL DDL, transactional loading, foreign keys, reference queries, and every shipped Grafana panel execute over real tables-v2 adapter output. | [ingestion contract verifier](../tools/verify_ingestion_contract.py), [generated asset contract](../tools/render_ingestion_assets.py) |
| Watch and process lifecycle | Same-size/same-second edits trigger reruns; coverage wrappers unwind; repeated runs bound deferred, symbol, namespace, file, and process resources. | [watch tests](../tests/test_watch.q), [soak verifier](../tools/verify_soak.py) |
| Installation and distribution | Exact-revision empty-prefix installs and externally symlinked `resq`, `qspec`, and `resq-merge` launchers resolve the installed root and quickstart. | [installation verifier](../tools/verify_installation.py), [quickstart tests](../examples/quickstart/test) |
| Scale | Required 10k green/failure-heavy reports and adapters stay within checked time/memory budgets; the recorded 100k run qualifies lifecycle/report growth but is not a per-commit minimum. | [scale verifier](../tools/verify_report_scale.py), [scale contract tests](../tools/tests/test_report_scale.py) |
| Supply chain and release | Workflow actions are immutable SHA pins, checkout credentials are not persisted, evidence is checksummed, and tags must resolve to the audited commit. | [release policy tests](../tools/tests/test_release_gate.py), [release gate](../tools/verify_release_gate.py) |
| External adoption | Two pinned MIT q codebases pass their declared normal/isolate inventories; no broader ecosystem compatibility is inferred. | [external-pilot verifier](../tools/verify_external_pilots.py), [pilot manifest](../pilots/manifest.json) |

Historical audits record only their named version and commit. Roadmap entries
label unimplemented ecosystem ideas explicitly; targeted internal fault
injection is not advertised as a mutation-testing product.
