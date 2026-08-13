-- Reference warehouse layout for tools/resq_to_tables.py output.
-- IDs and paths are ordinary columns, not metric/log labels.
CREATE TABLE resq_runs (
  run_id TEXT PRIMARY KEY,
  started_at TIMESTAMPTZ NOT NULL,
  finished_at TIMESTAMPTZ NOT NULL,
  service TEXT,
  environment TEXT,
  deployment_id TEXT,
  artifact_digest TEXT,
  vcs_sha TEXT,
  status TEXT NOT NULL,
  test_count INTEGER NOT NULL,
  fail_count INTEGER NOT NULL,
  error_count INTEGER NOT NULL
);

CREATE TABLE resq_tests (
  run_id TEXT NOT NULL REFERENCES resq_runs(run_id),
  execution_id TEXT NOT NULL,
  test_id TEXT NOT NULL,
  case_id TEXT,
  suite TEXT NOT NULL,
  description TEXT NOT NULL,
  status TEXT NOT NULL,
  duration_seconds DOUBLE PRECISION NOT NULL,
  file_path TEXT,
  message TEXT,
  PRIMARY KEY (run_id, execution_id)
);

CREATE TABLE resq_attempts (
  run_id TEXT NOT NULL,
  execution_id TEXT NOT NULL,
  attempt INTEGER NOT NULL,
  status TEXT NOT NULL,
  duration_seconds DOUBLE PRECISION NOT NULL,
  message TEXT,
  PRIMARY KEY (run_id, execution_id, attempt),
  FOREIGN KEY (run_id, execution_id)
    REFERENCES resq_tests(run_id, execution_id)
);

CREATE TABLE resq_benchmarks (
  run_id TEXT NOT NULL REFERENCES resq_runs(run_id),
  benchmark_id TEXT NOT NULL,
  test_id TEXT NOT NULL,
  metric TEXT NOT NULL,
  unit TEXT NOT NULL,
  avg_time_ms DOUBLE PRECISION,
  comparison_class TEXT,
  PRIMARY KEY (run_id, benchmark_id)
);

CREATE TABLE resq_coverage_files (
  run_id TEXT NOT NULL REFERENCES resq_runs(run_id),
  coverage_file_key TEXT NOT NULL,
  file_path TEXT NOT NULL,
  function_found INTEGER NOT NULL,
  function_hit INTEGER NOT NULL,
  line_found INTEGER NOT NULL,
  line_hit INTEGER NOT NULL,
  PRIMARY KEY (run_id, coverage_file_key)
);

CREATE TABLE resq_coverage_sites (
  run_id TEXT NOT NULL,
  coverage_file_key TEXT NOT NULL,
  coverage_site_key TEXT NOT NULL,
  site_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  hits INTEGER NOT NULL,
  PRIMARY KEY (run_id, coverage_site_key),
  FOREIGN KEY (run_id, coverage_file_key)
    REFERENCES resq_coverage_files(run_id, coverage_file_key)
);

-- Immutable deployment correlation: artifact digest or commit SHA plus the
-- bounded environment/service labels. A branch name alone is not immutable.
SELECT r.service, r.environment, r.artifact_digest, r.vcs_sha,
       r.run_id, r.fail_count, r.error_count
FROM resq_runs AS r
WHERE r.service = :service
  AND r.environment = :environment
ORDER BY r.finished_at DESC;

-- Coverage context -> test result join through the stable test identifier.
SELECT c.context_id, c.test_id, t.status, m.kind, SUM(m.hits) AS hits
FROM resq_coverage_contexts AS c
JOIN resq_tests AS t
  ON t.run_id = c.run_id AND t.test_id = c.test_id
JOIN resq_coverage_context_metrics AS m
  ON m.run_id = c.run_id AND m.coverage_context_key = c.coverage_context_key
GROUP BY c.context_id, c.test_id, t.status, m.kind;
