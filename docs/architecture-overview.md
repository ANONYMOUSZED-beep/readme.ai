# Architecture Overview

This is a condensed reference of the system design established in **Sprint 0.1**.
It describes the target architecture; not all components are implemented yet.

## Mission constraint

ReadMe.ai must **preserve reading flow**. The single most important architectural
consequence is that the system should *rarely generate an explanation while the
user waits* — it should mostly serve artifacts pre-computed during analysis. This
drives the split between a fast **synchronous path** (the reader) and an
**asynchronous processing path** (ingestion and analysis).

## Components

| Component | Technology | Responsibility |
| --- | --- | --- |
| Frontend | Flutter | Reading client; thin on logic, rich on experience; never blocks reading on the network |
| Backend | FastAPI | Synchronous orchestration, authorization boundary, input validation |
| Learning Intelligence Engine | backend | Learner-aware layer above explanations; runs pluggable capabilities, then delegates to the Explanation Service (ADR 0008) |
| AI Layer | Ollama → cloud | Inference behind a stable internal contract; prompt assembly; faithfulness validation |
| Storage | Cloudflare R2 | Source files and large derived artifacts (references stored in DB) |
| Database | PostgreSQL | System of record; strong consistency for progress/plans |
| Vector DB | Qdrant | Embeddings for grounded retrieval; fully rebuildable derived store |
| Auth | Firebase Auth | Identity provider; backend keeps its own user record keyed by UID |
| Workers | background tier | Ingestion, analysis, plan generation, explanation pre-computation |

## Key principles

1. **Separate the synchronous reader path from asynchronous processing.**
2. **Quarantine all model access behind one AI Service** so the model can change
   (Ollama → cloud) as a configuration change, not a rewrite.
3. **Preserve reading flow through pre-computation and caching**, not on-demand
   generation.
4. **All derived data is rebuildable** from the source file plus versioned prompts.
5. **Anchor progress and annotations to stable text offsets**, never page numbers.

## Module map (target)

```
Auth, Settings          (base layer — depended on by everything)
Books, Storage          (the book aggregate and its files)
AI                       (leaf utility — embeddings, generation, validation)
Reader, Explanation,     (capability modules built on the above)
Reading Plan, Progress,
Bookmarks, Library
Ingestion, Analysis      (asynchronous; feed everything else)
```

See the full Sprint 0.1 blueprint for entity design, scalability stages, and the
risk register.
