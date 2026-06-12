# resQ Skill for Claude Code

`SKILL.md` is a self-contained skill file for [Claude Code](https://claude.com/claude-code) and other agent runtimes that load skills from `~/.claude/skills/`. With this installed, an LLM working in any q project that uses resQ can answer questions like "add a test for this function" or "set up resQ here" without needing the user to paste docs.

## Install

```bash
mkdir -p ~/.claude/skills/resq
cp skill/SKILL.md ~/.claude/skills/resq/SKILL.md
```

That's it. Next time you start Claude Code in a q project, the `resq` skill is available.

## What it covers

- Setup against three scenarios: an existing on-disk install, vendoring, or a global install.
- Project layout, discovery conventions, and `resq.json`.
- The canonical test-file pattern (incl. the `.utl.FILELOADING`-relative SUT loader).
- Block keywords (`should`/`before`/`beforeAll`/`skip`/`pending`/`skipIf`/`retry`/`testOnly`/`holds`/`perf`/`alt`) and the `#tag` filtering convention.
- The full assertion table (incl. `mustthrow` glob semantics, `mustdelta` arity, and the camelCase aliases), fuzz (`holds`), and the mock-vs-spy decision (only `spy` records calls).
- Cleanup scopes (`registerCleanup` vs `registerSpecCleanup`) and fixtures.
- CLI flags, verified exit codes (0/1/3/4), and CI/JUnit wiring.
- q-flavour pitfalls that bite test authors specifically (operator precedence in assertions, single-char string vs char atom, the `` `sym!`sym `` shorthand trap, spaced-path `'nyi`).
- A pre-emit verification checklist for the assistant to run before returning code.

For general q syntax/idioms (not test-specific), load the companion `q-kdb` skill alongside this one.

## Keeping it in sync

`SKILL.md` lives in this repo so it travels with the framework. When resQ's behaviour changes in a way that affects test authors (new flags, new APIs, new pitfalls), update `SKILL.md` in the same PR and bump the relevant section. Users re-install with the same `cp` command.
