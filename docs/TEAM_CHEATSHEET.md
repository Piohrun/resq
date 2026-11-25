# resQ on one page

resQ has many options; a team needs about five commands. This page is those,
the exit codes, and a CI recipe. Everything else is in the
[API reference](API_REFERENCE.md) when you need it.

Runs on Linux with q 4.1 (q 4.0 is verified). `-isolate` and `resq mutate`
also need GNU `timeout`.

## Once per project

Put `resq.json` at the top of the project:

```json
{
  "strict": true,
  "outDir": "artifacts/tests",
  "coverageSources": ["src"]
}
```

`strict` turns a test that asserts nothing, or a run that runs nothing, into a
failure. Commit `.resq/quarantine.json` if you ever create one; the rest of
`.resq/` is local state and ignores itself in git.

## Five commands

```bash
resq test tests/                      # before you push
resq test tests/ -last-failed         # while fixing: only what failed last time
bin/qspec tests/                      # an existing qspec suite, unchanged
resq cover tests/ --source src/ -cov-contexts     # which code each test runs
resq mutate src/ -since main          # would your tests notice a bug in what you changed?
```

- `resq test` runs every `test_*.q` under the path. Add `-isolate` to run
  each file in its own q process, so an `exit` or a hang fails that file only.
- `-last-failed` runs the whole selection when none of last run's failures is
  in it, and says so.
- `bin/qspec` keeps qspec's assertion semantics and report formats, so a
  suite written for qspec moves over without edits.
- `resq cover` writes LCOV, HTML and JSON. It measures code your tests load
  with `\l`, `system "l ..."`, `.utl.require` or a loader of your own. Add
  `-cov-statements` for line data.
- `resq mutate` changes one thing at a time in the functions on the lines you
  changed, and reports each change your tests did not catch. A survivor is a
  test worth writing.

## What the exit code means

| Code | Meaning |
|---:|---|
| 0 | All passed |
| 1 | A test failed, or under `strict` nothing ran or a test asserted nothing |
| 3 | No test files found |
| 4 | A test file did not load |
| 130 | Interrupted; no report was written |

## CI recipe

```bash
# 1. Correctness: each test file in its own q process
resq test tests/ -isolate -isolateWorkers 4 -junit -json -outDir artifacts/tests

# 2. Coverage: a run of its own (coverage and -isolate do not combine)
resq cover tests/ --source src/ -cov-statements -cov-branches -cov-contexts \
  -json -outDir artifacts/coverage

# 3. On a pull request: mutants on the changed lines only
resq mutate src/ -since origin/main -isolateWorkers 4 -json -outDir artifacts/mutation
```

Each step's exit code is the verdict; the reports carry the detail. Workers
each use a q licence slot. More in [Continuous Integration](CI.md).

## With an AI assistant

Point it at [`skill/SKILL.md`](../skill/SKILL.md). It covers writing tests
that assert something, the q pitfalls tests hit most, and these commands.

## When something looks wrong

[Troubleshooting](TROUBLESHOOTING.md) covers load errors, strict failures,
coverage gaps and isolation timeouts.
