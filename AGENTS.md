# Agent guidance

## Code intelligence

These rules apply to the primary agent and delegated subagents.

- When `.codegraph/` exists and a task requires non-trivial source discovery,
  call-path tracing, dependency analysis, or blast-radius analysis, use
  CodeGraph before reconstructing that information with raw searches and file
  reads.
- Do not initialize CodeGraph in new, small, or unindexed repositories. Indexing
  is an explicit user choice.
- Raw search and direct reads remain appropriate for configuration,
  documentation, generated files, or details CodeGraph does not provide.
- For semantic work on `.q` files, use q-lsp definitions, references, and hover
  when the q-lsp tools are available and relevant to the task.
- Run q-lsp diagnostics on changed `.q` files before completion. Treat q runtime
  tests as authoritative for execution semantics; static diagnostics complement
  them but do not replace them.
- If either optional tool is unavailable or stale, fall back normally. Mention
  the limitation only when it materially reduces confidence.
