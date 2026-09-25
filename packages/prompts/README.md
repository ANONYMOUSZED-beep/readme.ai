# packages/prompts

Versioned LLM prompt templates, treated as reviewed assets rather than inline
strings.

## Responsibility (target)

- Store prompt templates under version control with explicit version
  identifiers.
- Allow every AI output to be tagged with the `prompt_version` that produced it,
  enabling cache invalidation and quality evaluation when prompts change.
- Subject prompt changes to code review like any other asset.

## Status

**Not yet extracted.** The explanation prompts currently live with the backend
in [`apps/api/app/prompts`](../../apps/api/app/prompts), each with a version
constant (e.g. `WORD_EXPLANATION_PROMPT_VERSION`). They move here once a second
consumer (such as the background workers) needs them.
