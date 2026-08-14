# Ingesting resQ evidence

The report-v2 artifact is the authoritative evidence record. For a warehouse,
data lake, or observability backend, normalize it with:

```bash
python3 tools/resq_to_tables.py test-results.json \
  --coverage coverage.json --out resq-tables.json
```

The output conforms to
[`schema/resq-ingestion-tables-v1.schema.json`](schema/resq-ingestion-tables-v1.schema.json).
Its tables and stable joins are:

| Table | Primary identity | Parent join |
|---|---|---|
| `runs` | `runId` | — |
| `tests` | `runId`, `executionId` | `runs.runId` |
| `attempts` | `runId`, `executionId`, `attempt` | `tests` |
| `benchmarks` | `runId`, `benchmarkId` | `runs`; `testId` may join `tests` |
| `diagnostics` | `diagnosticKey` | `runs.runId` |
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

The reference SQL is
[`examples/resq_ingestion.sql`](examples/resq_ingestion.sql). The example
Grafana dashboard is
[`examples/grafana-resq-overview.json`](examples/grafana-resq-overview.json).
Deployment correlation uses an immutable artifact digest or commit SHA together
with supplied environment/service labels; branch name alone is insufficient.

## VCS and CI context

resQ executes at most one cached Git status probe per run. `-no-vcs` or
`"vcsProbe": false` disables it; outside a Git repository the status is
`unavailable` and the run continues. CI variables are normalized for GitHub
Actions, GitLab CI, Azure Pipelines, Jenkins, CircleCI, Buildkite, TeamCity, and
Bamboo. Unknown systems use the `generic` provider plus explicit run labels
rather than exposing arbitrary environment variables.
