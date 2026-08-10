# ADR 0003 — Quarantine Model Access Behind a Single AI Service

- **Status:** Accepted (forward-looking; no AI code in this sprint)
- **Date:** Sprint 0.2

## Context

The MVP starts with local Ollama but will move to a scalable cloud model. The
model is the least reliable, slowest, and most expensive dependency, and it will
change.

## Decision

All model access (embeddings, generation, validation) is mediated by a single
internal **AI Service** with a stable contract. No business module ever calls a
model provider directly.

## Rationale

- The Ollama → cloud transition becomes a configuration change, not a rewrite.
- Retries, timeouts, fallbacks, latency/cost policy, and model+prompt versioning
  live in exactly one place.
- The AI Service can be faked in tests, making business logic deterministic.

## Consequences

- A small amount of indirection is accepted in exchange for replaceability.
- Every AI output carries model + prompt version metadata for cache invalidation
  and quality evaluation.
