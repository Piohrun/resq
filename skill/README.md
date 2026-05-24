# resQ Skill for Claude Code

`SKILL.md` is a self-contained skill file for [Claude Code](https://claude.com/claude-code) and other agent runtimes that load skills from `~/.claude/skills/`. With this installed, an LLM working in any q project that uses resQ can answer questions like "add a test for this function" or "set up resQ here" without needing the user to paste docs.

## Install

```bash
mkdir -p ~/.claude/skills/resq
cp skill/SKILL.md ~/.claude/skills/resq/SKILL.md
```

That's it. Next time you start Claude Code in a q project, the `resq` skill is available.

## What it covers

- Detecting an existing resQ install or wiring a fresh one in.
- Project layout, discovery conventions, and `resq.json`.
- The full assertion / mock / spy / fixture / snapshot DSL.
- Cleanup scopes (`registerCleanup` vs `registerSpecCleanup`) and when to use which.
- CLI flags and exit codes.
- q-flavour pitfalls that bite test authors specifically (operator precedence in assertions, single-char string vs char atom, the `` `sym!`sym `` shorthand trap).
- Step-by-step bootstrap checklist for adding resQ to an existing repo.
- A pre-emit verification checklist for the assistant to run before returning code.

For general q syntax/idioms (not test-specific), load the companion `q-kdb` skill alongside this one.

## Keeping it in sync

`SKILL.md` lives in this repo so it travels with the framework. When resQ's behaviour changes in a way that affects test authors (new flags, new APIs, new pitfalls), update `SKILL.md` in the same PR and bump the relevant section. Users re-install with the same `cp` command.
