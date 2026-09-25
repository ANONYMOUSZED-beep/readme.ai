# ADR 0002 — Flutter Architecture: Feature-first + Riverpod + GoRouter

- **Status:** Accepted
- **Date:** Sprint 0.2

## Context

The client's most complex and latency-sensitive surface is the reader. We need
an architecture that keeps features independently evolvable, keeps domain logic
testable without a widget tree, and handles derived/async/cached state cleanly.

## Decision

- **Feature-first** organization with a pragmatic Clean layering
  (`presentation` / `domain` / `data`) inside each feature.
- **Riverpod** for both state management and dependency injection.
- **GoRouter** for declarative, URL-based navigation.
- **Dio** for HTTP, **Freezed** + **json_serializable** for immutable models.

## Rationale

- Feature-first localizes change; grouping by technical layer makes every change
  touch everything.
- Riverpod expresses derived/async/cached state cleanly and disposes of it
  predictably (important for memory when a large book is open). It also serves as
  the DI container, removing the need for a second DI library.
- A single state solution avoids the real failure mode of mixing libraries.

## Consequences

- One pattern is standardized across all features.
- Code generation (Freezed/JSON) is part of the build (`build_runner`).
