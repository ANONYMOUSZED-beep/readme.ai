# ADR 0008 — Learning Intelligence Engine (LIE)

- **Status:** Accepted
- **Date:** Sprint 5.0

## Context

ReadMe.ai should first understand the learner, then help — rather than only
answering questions. As educational intelligence grows (prerequisites,
confidence, memory, recommendations, revision), we need one place for
learner-aware decisions that does not bloat the Explanation Service or leak into
the reader.

## Decision

Introduce the **Learning Intelligence Engine (LIE)**, a layer that sits *above*
the Explanation Service:

```
Reader → Explanation API → LIE → Capability Pipeline → Explanation Service → Provider
```

1. **The reader is unaware of LIE.** The explanation endpoint is unchanged; the
   router simply delegates to the engine instead of the service.

2. **Capabilities are pluggable.** Each learner-aware decision is a
   `LearningCapability` (`evaluate(context) -> CapabilityOutcome`). The engine
   runs registered capabilities, aggregates their results, then delegates
   explanation generation to the Explanation Service and merges the outcome into
   the response (currently `prerequisites`).

3. **A registry decouples the engine from implementations.** Capabilities
   register at the composition root; the engine never imports concrete
   capabilities. Adding a future capability = implement `LearningCapability` +
   register it. No engine change.

4. **Responsibilities stay separated.** LIE makes learning decisions; the
   Explanation Service still generates explanations (ADR 0003 provider
   abstraction unchanged — the reader never touches the model).

5. **The foundation ships one capability.** `PrerequisiteCapability` is
   deterministic (a configurable dependency map), not AI. It may become
   AI-powered later without changing the engine, registry, or API.

## Consequences

- The response gained an optional `prerequisites` field (empty list is valid);
  existing clients are unaffected.
- A misbehaving capability is caught and skipped — it cannot break explanations.
- Future intelligence (confidence, memory, recommendations, revision) is added
  as capabilities, keeping the engine free of feature-specific logic.
