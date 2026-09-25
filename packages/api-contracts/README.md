# packages/api-contracts

The **single source of truth** for request/response shapes shared between the
Flutter client (`apps/mobile`) and the FastAPI backend (`apps/api`).

## Responsibility (target)

- Hold the canonical contract definitions for the product API.
- Prevent frontend/backend drift by generating typed models for both sides from
  one definition (e.g. via the backend's OpenAPI schema).

## Status

**Not yet extracted.** The product API's contract is currently the backend's
OpenAPI schema (`/openapi.json`, served in development), and the Flutter client
hand-writes matching DTOs in each feature's `data/` layer. Generating both sides
from one definition here is the intended next step.
