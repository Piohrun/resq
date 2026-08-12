# External adoption pilots

resQ's release gate includes offline, repeatable tests against two public q
codebases. These are adoption evidence, not a claim that every feature of either
project has been certified.

## Pinned corpus

| Project | Pinned commit | Why it is representative | Adoption mode |
| --- | --- | --- | --- |
| [strQ](https://github.com/aa1024/strQ) | `7fa050ffaf385477bc16e946c6ec8ca7955833d7` | A documentation-heavy utility library using namespaces, multiline functions, projections, and broad q value shapes | Production source is vendored without semantic changes; its 21 upstream assertions are expressed as three resQ tests |
| [reQ](https://github.com/jonathonmcmurray/reQ) | `6728dd50ed767ffb8818940a51579d4abc8c01d9` | A modular HTTP library whose public test already uses the qspec DSL and `.utl.require` | The upstream base64 implementation and qspec test run directly; only trailing blank-line/final-newline normalization is applied |

Both projects are MIT-licensed. Their licence files are retained beside the
vendored slices. [`pilots/manifest.json`](../pilots/manifest.json)
records repository URLs, exact commit SHAs, upstream hashes, vendored hashes,
and any line-ending/whitespace normalization. The verifier is entirely offline,
so an upstream branch movement cannot change a release result.

## Release check

Run:

```sh
tools/verify_external_pilots.py --q q
```

For every pilot, the check verifies provenance metadata and vendored hashes,
runs the corpus in normal and per-file isolated modes, validates each JSON v2
report, checks exact test/assertion counts, and requires identical stable-ID
verdicts. CI runs this check on the licensed q runner.

The current corpus covers a small standalone library and a qspec-based modular
library. Larger applications with IPC, tickerplant processes, databases, or
native extensions still need their own integration environment; the pilots do
not weaken the trust-boundary statement in [Security](../SECURITY.md).
