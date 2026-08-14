# Ingesting resQ evidence

The report-v2 artifact is the authoritative evidence record. For a warehouse,
data lake, or observability backend, normalize it with:

```bash
python3 tools/resq_to_tables.py test-results.json \
  --coverage coverage.json --out resq-tables.json
```

The output conforms to
[`schema/resq-ingestion-tables-v2.schema.json`](schema/resq-ingestion-tables-v2.schema.json).
Table contract v2 separates statement execution `hits` from branch
`edgesHit`, validates the detailed coverage artifact against its authoritative
`runId`, and includes host, q-version, and OS dimensions on `runs`. Consumers
that still require the old conflated branch `hits` field may request the named
compatibility projection with `--contract-version 1`; new pipelines must use
the default v2 contract.
Its tables and stable joins are:

| Table | Primary identity | Parent join |
|---|---|---|
| `runs` | `runId` | — |
| `tests` | `runId`, `executionId` | `runs.runId` |
| `attempts` | `runId`, `executionId`, `attempt` | `tests` |
| `benchmarks` | `runId`, `benchmarkId` | `runs`; `testId` may join `tests` |
| `diagnostics` | `diagnosticKey` | `runs.runId` |
| `coverageRuns` | `runId` | `runs.runId` |
| `coverageFiles` | `coverageFileKey` | `runs.runId` |
| `coverageFunctions` | `coverageFunctionKey` | `coverageFiles` |
| `coverageSites` | `coverageSiteKey` | `coverageFiles`/`coverageFunctions` |
| `coverageEdges` | `coverageEdgeKey` | `coverageSites` |
| `coverageContexts` | `coverageContextKey` | `runs`; `testId` may join `tests` |
| `coverageContextMetrics` | context + `metricId` | contexts, and file/site when present |

`caseId` is the execution identity for a parameterized case; otherwise the
execution identity is `testId`. Attempt identity is the parent execution plus
its one-based attempt number. Coverage site identity is scoped by run and file,
so equal site IDs in different files cannot collide.
Statement-site rows carry `hits`; branch-site rows carry `edgesHit`. These are
deliberately different measures and must not be aggregated into one column.

## Transactional SQL ingestion

The executable SQL contract lives in `tools/ingestion_contract.py`. It is the
single source for warehouse table/column mappings, foreign keys, inserts,
reference queries, and Grafana panel queries. Each SQL row also retains the
complete normalized object in `raw_payload`, so additive table-v2 fields are
not discarded before the warehouse schema projects them explicitly.

Run, validate, normalize, and commit one run to SQLite with:

```bash
bin/resq test tests -strict -json -cov -quiet -outDir artifacts/resq
python3 tools/resq_ingest.py artifacts/resq/test-results.json \
  --coverage artifacts/resq/coverage.json \
  --sqlite artifacts/resq/evidence.sqlite \
  --tables-out artifacts/resq/resq-tables.json
```

The PostgreSQL path uses the same validation, normalization, DDL, mappings,
foreign keys, and one-run transaction:

```bash
python3 tools/resq_ingest.py artifacts/resq/test-results.json \
  --coverage artifacts/resq/coverage.json \
  --postgres-dsn "$RESQ_POSTGRES_DSN" \
  --tables-out artifacts/resq/resq-tables.json
```

PostgreSQL loading requires psycopg 3. SQLite uses only the Python standard
library. The adapters are deliberately stateless: the warehouse owner remains
responsible for credentials, schema migration approval, retention, partitioning,
backup, and deletion policy. A rejected child join rolls back the entire run.

## Labels and cardinality

`run.labels` accepts at most 32 string values. Keys are lexical and sorted;
reserved framework prefixes are rejected. Prefer these shared keys:
`environment`, `service`, `deploymentId`, `artifactDigest`, `cluster`, `region`,
and `hostGroup`. Configuration is overlaid by `RESQ_LABELS_JSON`, then by
`-labels JSON`. Never put credentials, tokens, customer data, or raw test
content in labels.

For Prometheus or Loki, use only deliberately low-cardinality dimensions such
as `service`, `environment`, `cluster`, `region`, outcome `status`, test `kind`,
and CI `provider`. Keep `runId`, `testId`, `caseId`, commit SHA, artifact digest,
deployment ID, paths, suite/description text, and error messages as structured
fields. They are useful join keys but unsafe metric/log labels.

Generated PostgreSQL and SQLite references are
[`examples/resq_ingestion.sql`](examples/resq_ingestion.sql) and
[`examples/resq_ingestion_sqlite.sql`](examples/resq_ingestion_sqlite.sql).
The [example Grafana dashboard](examples/grafana-resq-overview.json) uses a
PostgreSQL datasource over those shipped tables—there are no assumed
Prometheus metrics. Its executable panels cover pass/fail rate, run duration,
per-test history, benchmark median/classification, coverage bases and
instrumentation completeness, test-context coverage, and
branch/deployment/host correlation.
Deployment correlation uses an immutable artifact digest or commit SHA together
with supplied environment/service labels; branch name alone is insufficient.

Regenerate checked examples after changing the contract with
`python3 tools/render_ingestion_assets.py --write`; CI runs the same renderer in
check mode, loads empty and populated contracts transactionally into SQLite,
executes every reference/dashboard query, and repeats the lane against the
documented PostgreSQL dialect.

## VCS and CI context

resQ executes at most one cached Git status probe per run. `-no-vcs` or
`"vcsProbe": false` disables it; outside a Git repository the status is
`unavailable` and the run continues. CI variables are normalized for GitHub
Actions, GitLab CI, Azure Pipelines, Jenkins, CircleCI, Buildkite, TeamCity, and
Bamboo. Unknown systems use the `generic` provider plus explicit run labels
rather than exposing arbitrary environment variables.
