# Versioning and deprecation policy

resQ follows Semantic Versioning for its documented public contracts. The
resQ release version, JSON `schemaVersion`, and qspec compatibility-contract
version are related but independent numbers.

## Public compatibility surface

The SemVer promise covers:

- documented DSL names, signatures, and assertion semantics;
- documented CLI commands/options, config keys, defaults, and process exit codes;
- the qspec surface listed in [QSPEC_COMPATIBILITY.md](QSPEC_COMPATIBILITY.md);
- JSON required fields/types/status meanings, JUnit/xUnit mappings, artifact
  names, and coverage gate meanings;
- stable test/case identity inputs and algorithms described in
  [IDENTITY.md](IDENTITY.md);
- execution-manifest schema v2, lifecycle-event schema v1, and the documented
  `.resq` observer/reporter registration and failure policy;
- benchmark-baseline, flake-history/quarantine, snapshot-inventory, property
  replay, and merged-shard artifact versions documented by their owning tools;
- the supported runtime/execution matrix and trust-boundary guarantees.

Unlisted `.tst.*`, `.resq.*`, `.utl.*`, implementation files, callback objects,
console whitespace/colour, debug messages, and in-memory table layouts are
private. A public document or compatibility contract can explicitly promote an
otherwise internal-looking name.

## Release meaning

- **Patch:** compatible correctness/security fix, diagnostic clarification, or
  documentation correction. A fail-closed fix may turn a false green into a
  failure without being considered an API break; the changelog must call this out.
- **Minor:** additive DSL/CLI/config capability, new reporter/coverage metadata,
  newly supported runtime, or opt-in behavior. Existing valid consumers and
  invocations continue to work.
- **Major:** removal/rename, incompatible default or semantic change, dropping a
  supported runtime, changing an exit-code meaning, stable-identity algorithm,
  or required machine-report field/type/status.

JSON schema v2 is forward-extensible: optional fields may be added in a minor
release, and consumers must ignore unknown fields. Its original required core is
`schemaVersion`, `framework`, `frameworkVersion`, `run`, `summary`, `tests`,
`performance`, `coverage`, and `diagnostics`; fields added after 1.0 remain
optional to a v2 consumer even when current producers always emit them. Required-
field removal/type change, closing an open classifier to future values, or
semantic reinterpretation requires a new `schemaVersion` and a major resQ
release unless both representations coexist through deprecation. The checked-in
schema and dependency-free validator accept original 1.0 artifacts and additive
extensions while strictly validating every recognized extension that is present.

## Deprecation lifecycle

1. Mark the item deprecated in API/migration docs and `CHANGELOG.md`.
2. Emit one actionable warning per run when resQ can detect its use; state the
   replacement and earliest removal major.
3. Keep it working for at least one complete minor-release cycle and 90 days.
4. Remove it only in the next major release, with a migration entry and test.

Security, data-loss, or false-green behavior may be disabled sooner when no safe
compatibility shim exists. That exception requires a prominent release note,
an actionable diagnostic, and the narrowest practical patch.

In-process plugins are trusted extensions, not a security boundary. Their
documented registration, dispatch, state-restoration, and strictness semantics
are public; arbitrary plugin side effects remain outside resQ's guarantees.

## Release mechanics

A release commit updates `.resq.VERSION`, README installation examples,
`CHANGELOG.md`, schema/examples when relevant, and passes the current
[release checklist](RELEASE_CHECKLIST.md) plus the applicable delivery ledger
([1.0](ROADMAP_1_0.md) or [post-1.0](ROADMAP_POST_1_0.md)). Tags use
`vMAJOR.MINOR.PATCH`; published code and generated reports must contain the same
version, and the tagged workflow rejects a mismatch before running q.
