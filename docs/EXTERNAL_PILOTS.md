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

## Upstream qspec differential

The pilots above run through resQ only. The differential check runs real
qspec next to resQ: unmodified [nugend/qspec](https://github.com/nugend/qspec)
on [nugend/qutil](https://github.com/nugend/qutil) and `bin/qspec` execute the
same suites the way a CI script calls them (`--junit <dir> > results.xml`,
with qutil loaded from q's startup file as a qutil install does).

| Project | Pinned commit | Runs |
| --- | --- | --- |
| [cryptoq](https://github.com/asatirahul/cryptoq) | `ffc72c1cdc487595df82de5a7969100bf0c4ade7` | whole suite, `--only=SHA,HMAC`, `--exclude=SHA`, `--xunit` |
| [qutil](https://github.com/nugend/qutil) | `2bce9deb5585f7166052bfb81012b8d897fedeeb` | its own test suite (`--junit` and `--xunit`), which includes failures upstream too |
| [qspec](https://github.com/nugend/qspec) | `9b846b68a8d808e472ba504d18c325b14b468087` | its own test suite |

All three are MIT-licensed and vendored unmodified under `pilots/vendor/`;
[`pilots/qspec-differential.json`](../pilots/qspec-differential.json) pins every
file's hash. Every testcase must appear in both reports (JUnit, or qspec's
`--xunit` file) under the same suite and name with the same verdict. The manifest lists the five permitted
differences with reasons: qspec's own tests of its private loader and halt
machinery, which are outside the [compatibility boundary](QSPEC_COMPATIBILITY.md).
A listed difference that stops occurring also fails the check.

```sh
tools/verify_qspec_differential.py --q q --out-dir artifacts/qspec-differential
```

The release gate and the licensed CI lane run it; the manifest and parser
contracts run in the licence-free lane. Running real suites this way found the
discovery, JUnit-on-stdout, qutil, `--name=value`, adverb and helper-surface
breakers that resQ's self-suite could not see.
