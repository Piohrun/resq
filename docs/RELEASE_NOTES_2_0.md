# resQ 2.0.0 release notes

resQ 2.0.0 is the major-version evidence-integrity release. It preserves the
documented q/resQ test DSL, CLI shape, report schema v2 compatibility, and qspec
surface while deliberately replacing identity v2 with geometry-independent,
typed identity v3. It also completes the correctness, scale, observability, and
operational findings discovered by the three-model cross-review and independent
follow-up audit.

## Identity and snapshot migration

Test, case, diagnostic, and manifest identities now length-frame their inputs.
Parameter values are encoded with q type, shape, structure, and canonical leaf
bytes before hashing; console width and precision cannot change an ID. Every
identity-bearing document records the algorithm and codec envelope, including q
version/release and local serialization capability. A mismatched q build or
codec is an explicit migration event, not a silent cache hit.

Rerun, flake, quarantine, and proposal state uses schema v2. Non-authoritative
mismatched state is preserved beside the original as an identity-mismatch
archive. Migrate only from complete old/new reports with
`tools/migrate_identity_state.py`; the command refuses missing, duplicate, or
ambiguous inventory mappings and never overwrites its destination. Review
quarantine policy explicitly—it remains blocking until migrated.

Text snapshots use the full-fidelity snapshot-v2 envelope. Legacy unversioned
text may have been truncated by q's display formatter, so resQ will not bless it
automatically. Use explicit snapshot update mode, inspect the complete rendering
diff, and commit the reviewed v2 file. Binary snapshots are unchanged. A q
codec/build mismatch likewise requires explicit review and migration.

## Correctness and evidence

- Benchmark regression statistics use sorted pooled ranks, correct tie
  variance, independently checked Mann–Whitney reference cases, global Holm
  correction, and a separate practical-effect threshold. Ad-hoc benchmark
  percentiles use linear interpolation at `(n - 1) * p`, including small n.
- JSON configuration normalizes numeric and list fields by declaration; seed
  keys accept an exact decimal string beyond JSON's safe integer range.
- Coverage can be initialized repeatedly in watch/no-exit processes. Statement,
  context, and report-assembly paths are indexed and bounded by repeated-sample
  performance and soak contracts. LCOV edge/path and fallback semantics are
  independently checked.
- Strict JSON emits no bare non-finite numbers. Measurement fields use `null`
  with `numericStatus`; arbitrary q evidence alone may use the versioned
  canonical-value envelope. XML durations and escaping share one fixed helper.
- Flake history merges partial observations without erasing unrelated IDs and
  ages unseen entries only after complete runs. Malformed caches do not abort
  execution; malformed quarantine policy never grants a pass.
- Typed property generators define deterministic edge/default domains,
  full-width GUIDs, bounded temporal values, bounded filtering, and replay-
  stable shrinking. Fixture, deferred-handle, static-discovery, and runner-
  outcome leak regressions are closed.

## Reporting, SQL, and scale

The default normalized ingestion contract is tables v2: statement `hits` and
branch `edgesHit` are separate, detailed coverage must match its report run,
and run rows include hostname, q, and OS dimensions. Existing consumers can use
the explicit `--contract-version 1` projection during migration.

`tools/resq_ingest.py` provides validated, transactional SQLite and PostgreSQL
loading. One executable contract generates both DDL dialects, foreign keys,
reference queries, and the checked PostgreSQL Grafana dashboard; no unshipped
Prometheus exporter is implied. NDJSON and tables retain complementary host and
label context, and every shipped dashboard query executes over adapter output.

Canonical report/event lifecycle assembly is indexed by file and suite. The
per-change gate covers 10k green and failure-heavy reports/adapters; the release
qualification also records the 100k lifecycle/report run and its environment.

## Process and supply-chain hardening

Isolation distinguishes a supervisor timeout from natural exit 124/137, likely
OOM/external SIGKILL, ordinary nonzero exit, and infrastructure failure. The
launcher traps INT/TERM, forwards the signal to its child session, escalates if
needed, reaps descendants, removes private scratch, and returns 130/143.
Externally symlinked `resq`, `qspec`, and `resq-merge` launchers are installation
contracts.

Every GitHub Action is pinned to a reviewed commit SHA, checkout does not retain
credentials, and weekly Dependabot updates require tag/SHA, release-note,
permission, and runner-behavior review.

## Deliberate scope

Production qualification remains kdb+/q 4.1.x 64-bit on Linux x86-64. Other q
releases, macOS, Windows, the optional AxLibraries self-coverage provider, and
unlisted projects/providers are not qualified by this release.

`await` and `eventually` are blocking polling helpers, not a q event loop; they
cannot dispatch future timer or IPC work while waiting. Local parallelism is
file-level child-process concurrency with a group barrier and one q runtime/
licence allocation per worker. resQ ships explicit trusted plugin callbacks,
not an IDE integration, plugin marketplace, or mutation-testing product.

## Install

```sh
git clone --branch v2.0.0 https://github.com/Piohrun/resq.git ~/.local/share/resq
ln -s ~/.local/share/resq/bin/resq ~/.local/bin/resq
ln -s ~/.local/share/resq/bin/qspec ~/.local/bin/qspec
ln -s ~/.local/share/resq/bin/resq-merge ~/.local/bin/resq-merge
resq --version
```

Pin the immutable tag in automation. The release is complete only when the
remote annotated `v2.0.0` tag resolves to the exact clean-clone evidence commit.
