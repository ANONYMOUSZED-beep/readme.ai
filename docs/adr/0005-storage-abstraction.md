# ADR 0005 — Storage Abstraction for Uploaded Files

- **Status:** Accepted
- **Date:** Sprint 2.0

## Context

The Library Foundation must persist uploaded book files. Local development
should not require cloud credentials, but production will use an object store
(Cloudflare R2). The Book module must not depend on which backend is in use.

## Decision

1. **A minimal `StorageService` protocol** (`save`, `delete`, `exists`) keyed by
   an opaque string. This is all CRUD requires and is satisfiable by both a
   local filesystem and an object store.

2. **Only `LocalStorageService` is implemented this sprint.** It writes files
   under a configured base directory, delegates blocking I/O to a worker thread,
   and validates keys to prevent path traversal. The R2 implementation is *not*
   written yet.

3. **A single provider resolves the implementation** based on
   `STORAGE_BACKEND`. This is the only place that knows the concrete backend, so
   introducing `CloudflareStorageService` later is a change to the provider
   alone — the Book module, which depends only on the protocol via DI, is
   untouched. This follows ADR 0003's "quarantine external dependencies behind a
   stable contract" principle.

4. **The database stores only a `storage_key`**, never file bytes. Keys are
   namespaced per user (`users/{user_id}/books/{book_id}{ext}`).

## Consequences

- Swapping to R2 requires implementing the protocol and one provider branch.
- Tests inject an in-memory fake storage; the local implementation is unit
  tested against a temp directory.
- File serving/download is out of scope until the Reader sprint.
