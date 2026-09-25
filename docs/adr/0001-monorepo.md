# ADR 0001 — Multi-package Monorepo

- **Status:** Accepted
- **Date:** Sprint 0.2

## Context

ReadMe.ai is built by a small team over six months and spans a Flutter client,
a FastAPI backend, background workers, and shared contracts. We must choose
between multiple repositories and a single monorepo.

## Decision

Use a single **monorepo** with clear top-level separation (`apps/`, `services/`,
`packages/`, `infra/`, `docs/`, `tooling/`).

## Rationale

- Atomic cross-cutting changes (e.g. changing a shared contract and both sides
  that consume it) land in one commit/PR.
- Single source of truth for contracts in `packages/api-contracts` prevents
  frontend/backend drift.
- Lower operational overhead for a small team than coordinating many repos.
- Module boundaries are explicit, so any component can be extracted into its own
  repo later without untangling hidden coupling.

## Consequences

- CI must scope jobs by changed paths to stay fast.
- Tooling for two ecosystems (Dart, Python) lives side by side; hooks and CI are
  path-scoped to keep them independent.
