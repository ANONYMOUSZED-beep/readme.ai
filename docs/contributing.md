# Contributing

## Branch strategy

Trunk-based development with short-lived branches off `main`.

| Prefix | Purpose |
| --- | --- |
| `feature/` | New capability (`feature/reader-progress`) |
| `fix/` | Bug fix (`fix/health-timeout`) |
| `chore/` | Tooling, deps, config (`chore/bump-ruff`) |
| `docs/` | Documentation only |
| `refactor/` | Behaviour-preserving change |

Rules:
- Branch from `main`, keep it short-lived, rebase rather than let it diverge.
- No long-lived feature branches during the six-month build.
- `main` is always green and deployable.

## Commit convention

[Conventional Commits](https://www.conventionalcommits.org/), imperative mood.

```
<type>(<scope>): <summary>

<body — explain WHY, not what>
```

Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `build`, `ci`, `perf`.

Examples:

```
feat(reader): add stable-offset progress anchoring
chore(api): configure structured json logging for production
docs(adr): record decision to quarantine model access behind AI Service
```

## Pull requests

- One logical change per PR; keep them small and reviewable.
- PR description: summary, what was tested, anything intentionally left out.
- At least one approving review required. The **auth and AI paths require
  review** without exception.
- CI must pass (lint, type-check, tests, build) before merge.

## Code review checklist

- Correctness and tests for the change.
- Boundary adherence: no cross-module data access; no model calls outside the
  AI Service; no secrets in code or client.
- Naming and standards (see `coding-standards.md`).
- Security on upload / auth / AI paths.
- No TODO placeholders, fake implementations, or dead code.

## Definition of Done

- Compiles and runs; CI green.
- Tests added/updated and passing.
- Docs/ADRs updated when a decision or contract changed.
- No new lint, type, or format violations.
