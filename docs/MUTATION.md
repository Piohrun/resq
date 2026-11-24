# Mutation Testing

Coverage tells you a test ran a line. It does not tell you a test would fail if that line were wrong. `resq mutate` answers the second question: it plants one small bug at a time in your functions and re-runs the tests. A bug that no test notices is reported.

## Quick Start

```bash
resq mutate src/pricing.q
```

Name source files, directories, or line ranges. Tests are taken from `tests/` unless you pass `-tests`.

```text
Mutation testing
  Source: 1 file(s), 4 function(s), 22 mutant(s)
  Tests:  1 file(s), each first run on its own without a mutant
  .
  Running mutants (. killed, S survived, T timed out, - not applied, E error)
  ..S.SS..SS......SSS

RESULT
  killed        11
  timed out     0
  survived      8
  not covered   3
  not assessed  0

  Mutation score: 50.0% (11 of 22 mutants detected)
  In functions the tests call: 57.9%

SURVIVED (8): the tests pass with this change in place
  src/pricing.q
    5:5   .app.price  statement removed: if[total<0; '"negative"]
    5:13  .app.price  `<` replaced with `<=`
    6:10  .app.price  `>=` replaced with `>`
    ...

NOT COVERED (3): no usable test file calls these functions by name
    src/pricing.q:10  .app.unused  (3 mutant(s))
```

Each survivor is a line and column, the function, and the change that went unnoticed. The first one above says: delete the negative-total check and every test still passes.

---

## Reading the Result

| Status | Meaning | What to do |
|---|---|---|
| **killed** | A test failed with the change in place. | Nothing. |
| **timed out** | The change made a test file run far longer than normal, usually an endless loop. Counted as detected. | Nothing. |
| **survived** | Every test that calls the function still passed. | Add an assertion that would fail, or decide the change does not matter (see *Equivalent mutants*). |
| **not covered** | No usable test file calls the function by name. | Write a test, or see *Limits* if the function is called through a captured value. |
| **not assessed** | The mutant could not be put in place, or the run failed for a reason other than the mutant. | Read the heading printed above the list: it says which. |

**Mutation score** is detected mutants (killed plus timed out) divided by detected, survived and not covered. Mutants that were not assessed are left out. The second figure leaves out uncovered functions too, so it measures only how well the tests check the code they do call.

---

## What Gets Mutated

Only the bodies of named functions defined at the top level of a file: `name:{...}`. Strings and comments are never changed.

| Mutator | Change | Example |
|---|---|---|
| `arithmetic` | `+` ↔ `-`, `*` ↔ `%`, and their assignment forms | `x+:1` → `x-:1` |
| `comparison` | `<` ↔ `<=`, `>` ↔ `>=`, `=` ↔ `<>` | `qty>=100` → `qty>100` |
| `logical` | `&` ↔ `\|`, `and` ↔ `or`, `all` ↔ `any` | `a and b` → `a or b` |
| `keyword` | `first` ↔ `last`, `min` ↔ `max`, `asc` ↔ `desc`, `lj` ↔ `ij`, and similar pairs; `not`, `neg`, `abs`, `distinct`, `reverse` removed | `distinct x` → `x` |
| `constant` | An integer moves by one (`0` ↔ `1`); `0b` ↔ `1b` | `til 10` → `til 11` |
| `condition` | The condition of `if[c;...]`, each condition of `$[c;a;...]`, and of `?[c;a;b]` is negated | `if[x>0;...]` → `if[not x>0;...]` |
| `statement` | One statement is removed | `validate x;` → nothing |

Some things are left alone on purpose:

- **Handles and internal functions.** `-1 "text"`, `h x` and `-4!x` are not arithmetic on a number.
- **Vector literals, floats, dates and nulls.** `1 2 3`, `0.9`, `2000.01.01`, `0N`.
- **`while` conditions.** Negating one mostly produces a loop that never ends.
- **A change that no longer parses, or that changes the function's parameters.** It is discarded.

---

## How It Runs

No source file is edited or copied.

1. **Baseline.** Each test file is run once on its own, unmutated, in a child process. A file that fails alone is left out and named, because a failure there under mutation would not be the mutant's doing. The same run records which target functions each test file calls.
2. **One mutant, one process.** For each mutant, resQ starts a normal `resq test <file>` child. The test file loads its source exactly as it always does. Then the one function is redefined in memory from its mutated text, and the tests run.
3. **Only the tests that call it.** A mutant is run against the test files whose baseline called its function, quickest file first, and stops at the first failure.

Because the swap happens in memory after loading, it does not matter how your project loads code: `\l`, `.utl.require`, or your own loader that computes a path from a module name and an environment root.

A mutant that hangs or crashes ends only its own process. A child is stopped once it has taken five seconds plus three times its baseline run.

### What keeps the verdicts honest

- **Exact match before mutating.** A function is changed only when the definition in memory is, character for character, the definition in the file. If a test file replaces the function, or the file is not what was loaded, the function is reported as not assessed.
- **Proof before a kill.** The child records that the mutant is in place before any test can run on it. A failing run without that record (a licence blip, a startup failure, an unstable test) is retried twice and then reported as not assessed. It is never counted as a kill. The record is only ever added to, so nothing that runs later can remove it.
- **No detection from an outside kill.** A child that resQ's own timeout stopped counts as timed out. A child killed with SIGKILL by anything else (the kernel's out-of-memory killer, a CI agent) is run again and then reported as not assessed.
- **No survivor on doubt.** If the child hit an error while keeping the mutant in place, a passing run is reported as not assessed: the mutant may not have been there for every test.
- **Same conditions for both runs.** The baseline and the mutant run each use one test file per process, so a test that only passes after another file has run cannot produce a false kill.

### Files a mutant changes

A function that writes a file may, as a mutant, write a different one. In a git checkout resQ looks at the working directory before the mutants run and after each batch, and lists what changed:

```text
FILES CHANGED (1): in the working directory while mutants ran; nothing was undone
    created  stray.txt  (during src/save.q:2 `0` replaced with `1`)
```

- **What is seen:** files created, modified or deleted under the working directory, and a changed file put back as committed (`restored`). Files git ignores are not looked at.
- **Which mutant:** with one mutant at a time, the one that was running. With `-isolateWorkers N`, one of the N in that batch; up to three are named.
- **What resQ does about it:** nothing. It will not delete or restore a file, because it cannot know the file is not yours. Remove strays yourself; `git status` shows them.
- **Large trees:** if one look takes more than half a second, resQ looks once at the end instead, and reports the change without naming a mutant.
- **Outside a git checkout** the run says it cannot list changed files, and carries on.

---

## Options

| Option | Purpose |
|---|---|
| `resq mutate src/a.q src/lib/` | Files and directories. A directory means every `.q` file under it that is not a test file. |
| `resq mutate src/a.q:10-40` | Only mutants on lines 10 to 40. `src/a.q:12` is one line. |
| `-tests PATHS` | Comma-separated test files or directories. Default `tests/`. |
| `-since REV` | Only mutants on lines changed since a git revision, including uncommitted changes. A file git does not track counts as entirely new. |
| `-mutators LIST` | Comma-separated mutator names from the table above. Default all. |
| `-max-mutants N` | Run an even sample of at most N mutants. |
| `-mutation-min N` | Exit 1 when the mutation score is below N percent, or cannot be computed. |
| `-isolateWorkers N` | Run N children at once. Each needs a q licence slot. Default 1. |
| `-isolateTimeout N` | Upper limit in seconds for any one child. Default 300. |
| `-json -outDir DIR` | Also write `DIR/mutation-report.json`. |
| `-quiet` | No progress marks. |

Test selection options (`-only`, `-exclude`, `-tag`, `-exclude-tag`) and loading options (`-root-load`, `-qspec-compat`, `-qspec-discovery`) are passed on to every child.

### Checking the tests for a change

```bash
resq mutate src/ -since main -isolateWorkers 4
```

This is the fastest useful run: it mutates only the lines your branch changed and tells you whether the tests would notice if those lines were wrong. It is a good check on tests that were written quickly, or generated.

### A qspec-style tree

The `qspec` launcher always runs tests. Use `resq` with the same compatibility flags:

```bash
resq mutate src/ -tests tests/ -qspec-compat -qspec-discovery
```

### Exit codes

| Code | Meaning |
|---|---|
| 0 | The run completed. Survivors do not change the exit code unless `-mutation-min` is set. |
| 1 | The score is below `-mutation-min`, no test file passes on its own, or the command line named something that does not exist. |

---

## The JSON Report

`-json` writes `mutation-report.json`:

```json
{
  "schemaVersion": 1,
  "kind": "resq-mutation-report",
  "summary": {"mutants": 22, "killed": 11, "timedOut": 0, "survived": 8,
              "notCovered": 3, "notAssessed": 0, "score": 50.0, "coveredScore": 57.9},
  "testFiles": [{"file": "tests/test_pricing.q", "usable": true, "reason": ""}],
  "filesChanged": [{"path": "stray.txt", "change": "created", "mutants": [3]}],
  "mutants": [
    {"id": 3, "file": "src/pricing.q", "line": 5, "column": 13, "function": ".app.price",
     "mutator": "comparison", "description": "`<` replaced with `<=`",
     "status": "survived", "killedBy": ""}
  ]
}
```

`status` is one of `killed`, `timeout`, `survived`, `uncovered`, `unloaded`, `unmatched`, `unapplied`, `error`. `uncovered` and `unloaded` are both reported as *not covered*: the first means the function was in memory but never called, the second that no test file loaded it. The last three are *not assessed*. `score` and `coveredScore` are `null` when nothing could be assessed. `filesChanged` lists each file with `change` (`created`, `modified`, `deleted` or `restored`) and the `id`s of the mutants that were running; the list of ids is empty when that is not known.

---

## Limits

- **Only named top-level functions.** Code that runs when a file loads, and lambdas stored inside a dictionary or list, are not mutated.
- **A function reached through a captured value looks uncovered.** If a dispatch table holds `.api.get` as a value taken at load time, a call through the table never goes through the name, so the mutant would not be reached and the call is not seen. The function is reported as not covered even when it is tested that way. A table that holds the function's name and looks it up at call time does not have this problem.
- **A call made while a test file loads is not seen.** Mutants and probes go in after loading.
- **Code a test reaches only through another process is not measured.** The mutant exists in the test's own q process. A test that starts a second q process and checks what that process does runs the unmutated code there.
- **A mutant runs your code with one thing changed, side effects included.** If a function writes or deletes files, a mutant of it may do so at a different path. resQ reports what changed in a git checkout (see *Files a mutant changes*) but does not prevent it or undo it. Mutate such code in a checkout you can restore.
- **Equivalent mutants.** Some changes cannot alter behaviour. Starting a sum at index 1 instead of 0 gives the same total, and no test can tell. These survive, and you have to recognise them. Expect a few per file; do not chase 100%.
- **Unstable tests.** A test that fails at random can kill a mutant it never touched. The mutant was in place, so resQ cannot tell the difference. Fix or quarantine unstable tests before trusting a score.
- **Time.** Each mutant costs one process start plus the tests that call its function, about a quarter of a second for a small test file. A mutant that hangs costs five seconds or more. Use line ranges, `-since`, `-max-mutants` and `-isolateWorkers` to keep runs short.
- **Tools.** The same as `-isolate`: a `timeout` command that supports `-k` and `--verbose`, plus `mktemp`, `chmod`, `rm` and `sh`.

---

## Troubleshooting

**Q: Every function is "not covered".**
A: Either the tests under `-tests` do not load the source you named, or they reach it only through captured values. Check that `resq test` on the same paths passes and exercises the code.

**Q: A function is "not assessed: the function in memory is not the definition in the file".**
A: Something redefined it after loading: a test file that replaces it, a second file that defines the same name, or a loader that rewrites source. resQ will not mutate a function it cannot match.

**Q: A test file was left out.**
A: It fails when run alone. The reason is printed. Run `resq test <file>` to see the failure. A file that depends on another test file having run first will always be left out.

**Q: Many mutants time out.**
A: They are in loops. That is expected and counted as detected, but slow. Raise `-isolateWorkers` so they overlap.

**Q: The score changes between runs.**
A: A test is unstable, or `holds` properties are drawing different inputs. Seed or fix them.
