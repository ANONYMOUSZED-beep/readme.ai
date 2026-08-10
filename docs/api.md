# API Reference

Base URL (local): `http://localhost:8000`

## Conventions

### Authentication

Protected endpoints require a Firebase ID token sent as a bearer token:

```
Authorization: Bearer <firebase-id-token>
```

The token is validated on **every** request (issuer, audience, expiry, and
signature against Google's published keys). There is no server session.

### Error envelope

All errors share one shape:

```json
{
  "error": {
    "code": "unauthorized",
    "message": "Authentication credentials were not provided.",
    "details": {},
    "request_id": "9d088443d2fc4bb49a7717055ad239fa"
  }
}
```

Codes: `validation_error`, `unauthorized`, `forbidden`, `not_found`,
`conflict`, `dependency_unavailable`, `internal_error`.

---

## Operational

| Method | Path | Auth | Description |
| --- | --- | --- | --- |
| GET | `/health` | none | Liveness — process is up |
| GET | `/health/ready` | none | Readiness — checks dependencies (503 if degraded) |
| GET | `/version` | none | Service name, version, environment |

---

## Authentication — `/api/v1/auth`

### GET `/api/v1/auth/me`

Returns the authenticated user, provisioning the internal record on first use.

- **Auth:** required.
- **200 OK**

```json
{
  "id": "0c8f4f1e-9b2a-4f3c-9b8e-1d2c3a4b5c6d",
  "email": "reader@example.com",
  "display_name": "Test Reader",
  "photo_url": "https://example.com/avatar.png",
  "created_at": "2026-06-29T12:00:00Z",
  "updated_at": "2026-06-29T12:00:00Z",
  "last_login_at": "2026-06-29T12:00:00Z"
}
```

- **401 Unauthorized** — missing, malformed, expired, or invalid token.

### POST `/api/v1/auth/logout`

Stateless acknowledgement of logout (the client discards its token).

- **Auth:** required.
- **200 OK**

```json
{ "detail": "Logged out." }
```

- **401 Unauthorized** — no valid token supplied.

---

## Library — `/api/v1/books`

All endpoints require authentication and operate only on the caller's own books.
Ownership is enforced in the service layer; accessing a book that does not
belong to the caller returns **404** (its existence is never revealed).

### POST `/api/v1/books`

Upload a book file (multipart/form-data) and create its library record.

- **Auth:** required.
- **Form fields:** `file` (required, the book file), `title` (optional; defaults
  to the file name).
- **201 Created** — returns the created book (see schema below).
- **422** — empty file or file exceeding `MAX_UPLOAD_SIZE_BYTES`.

### GET `/api/v1/books`

List the caller's books, newest first.

- **200 OK**

```json
{
  "items": [
    {
      "id": "0c8f4f1e-9b2a-4f3c-9b8e-1d2c3a4b5c6d",
      "title": "Clean Architecture",
      "original_filename": "clean_architecture.pdf",
      "mime_type": "application/pdf",
      "file_size": 1048576,
      "status": "UPLOADED",
      "total_pages": null,
      "cover_image_url": null,
      "uploaded_at": "2026-06-29T12:00:00Z",
      "created_at": "2026-06-29T12:00:00Z",
      "updated_at": "2026-06-29T12:00:00Z"
    }
  ],
  "total": 1
}
```

### GET `/api/v1/books/{book_id}`

Return a single owned book.

- **200 OK** — the book object (as above).
- **404 Not Found** — unknown or not owned.

### DELETE `/api/v1/books/{book_id}`

Delete an owned book and its stored file.

- **204 No Content** — deleted.
- **404 Not Found** — unknown or not owned.

**Book status** is one of: `UPLOADING`, `UPLOADED`, `PROCESSING`, `READY`,
`FAILED`. The Library Foundation only produces `UPLOADED`.

---

## Reader — `/api/v1/books/{book_id}`

All endpoints require authentication and operate only on the caller's own books
(ownership is enforced; a non-owned or unknown book returns **404**).

### GET `/api/v1/books/{book_id}/content`

Return the book's readable content.

- **200 OK**

```json
{
  "book_id": "0c8f4f1e-9b2a-4f3c-9b8e-1d2c3a4b5c6d",
  "title": "Notes on Reading",
  "format": "text",
  "content": "It was a bright cold day in April...",
  "character_count": 1234
}
```

`format` is `text` (reflowable content in `content`) or `unsupported`
(`content` is `null`). **Temporary limitation:** only already-textual files
render as `text`; PDF/EPUB report `unsupported` until a future parsing sprint.

### GET `/api/v1/books/{book_id}/progress`

Return saved reading progress, or `null` (200) if the book is unstarted.

```json
{
  "book_id": "…",
  "current_position": "1280",
  "progress_percentage": 42.5,
  "total_reading_time_seconds": 360,
  "last_read_at": "2026-06-29T12:00:00Z"
}
```

### PUT `/api/v1/books/{book_id}/progress`

Create or update the reading position. `reading_time_seconds` is added to the
accumulated total.

```json
{ "current_position": "1280", "progress_percentage": 42.5, "reading_time_seconds": 30 }
```

`current_position` is a stable anchor (character offset), not a page number.

### Bookmarks

| Method | Path | Description |
| --- | --- | --- |
| GET | `/api/v1/books/{book_id}/bookmarks` | List bookmarks (`{items, total}`) |
| POST | `/api/v1/books/{book_id}/bookmarks` | Create (`{anchor, label?}`) → 201 |
| DELETE | `/api/v1/books/{book_id}/bookmarks/{bookmark_id}` | Delete → 204 |

> The reader serves content reconstructed from the **structured document**
> produced by the processing engine (below), not from raw files. Only
> `COMPLETED` books return `format: "text"`.

---

## Processing — `/api/v1/books/{book_id}`

Uploading a book automatically triggers processing into a structured internal
document. All endpoints require authentication and enforce ownership (404 if not
owned).

### GET `/api/v1/books/{book_id}/processing`

Return processing status and extracted metadata.

```json
{
  "book_id": "…",
  "status": "COMPLETED",
  "processor_name": "plain_text",
  "title": "Chapter One",
  "author": null,
  "language": null,
  "page_count": null,
  "word_count": 1234,
  "character_count": 6789,
  "estimated_reading_minutes": 7,
  "error_code": null,
  "error_message": null,
  "processed_at": "2026-06-29T12:00:00Z"
}
```

- **404** if the book has not been processed.

`status` ∈ `QUEUED | PROCESSING | COMPLETED | FAILED`. On failure, `error_code`
is one of `unsupported_format`, `malformed_file`, `empty_document`, `too_large`,
`timeout`, `internal_error`.

### POST `/api/v1/books/{book_id}/processing`

Re-run processing (idempotent; replaces prior output). Returns the same shape.

---

## Explanation — `/api/v1/books/{book_id}`

Contextual explanation of a **selection** (not a chat). The backend classifies
the selection as word/sentence/paragraph using the structured document and picks
the strategy automatically — the client never chooses a mode. Requires
authentication; ownership enforced. The reader never calls the model directly —
requests pass through the explanation service to Ollama.

### POST `/api/v1/books/{book_id}/explain`

Request:

```json
{
  "anchor": "1280",
  "end_anchor": "1300",
  "selected_text": "the selected word, sentence, or paragraph"
}
```

`end_anchor` is optional; when omitted it is derived from the selected text
length. Both are stable character offsets (Sprint 3.5 anchors), not page
numbers.

Response (`200`):

```json
{
  "selection_type": "word",
  "explanation": "A concise explanation.",
  "meaning": "a brief definition (word selections only, else null)",
  "example": "one contextual example (word selections only, else null)",
  "prerequisites": [
    { "name": "Derivative", "reason": "Gradient descent builds upon derivatives." }
  ]
}
```

`prerequisites` is decided by the Learning Intelligence Engine (ADR 0008) and may
be an empty list. Requests flow through LIE, which runs learner-aware
capabilities before the Explanation Service generates the explanation; the
endpoint contract is otherwise unchanged.

- `selection_type` ∈ `word | sentence | paragraph`. Explanation length is bounded
  per type (word ≤3, sentence ≤5, paragraph ≤7 sentences).
- **401** — not authenticated. **404** — unknown/unowned book, or the book is not
  processed. **422** — selection is outside the processed content.
- **503** (`dependency_unavailable`) — model timeout, unsupported model, invalid/
  empty response, or provider unavailable (`details.reason`). Reader shows retry.

Configured via `OLLAMA_BASE_URL`, `OLLAMA_MODEL`, `OLLAMA_TIMEOUT_SECONDS`.

> Replaces the Sprint 4.1 `POST /explain/word` endpoint.
