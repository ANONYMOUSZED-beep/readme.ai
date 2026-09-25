# ADR 0006 — Reader Foundation: Content Abstraction & Stable Anchors

- **Status:** Accepted
- **Date:** Sprint 3.0

## Context

The Reader Foundation must deliver a premium reading experience over the files
uploaded in Sprint 2.0, with **no parsing pipeline, ingestion, or AI**. Uploaded
files are arbitrary book formats (often PDF), but the desired experience —
adjustable font size and line spacing, reflowing text — requires textual
content, which fixed-layout PDFs do not provide without parsing.

## Decisions

1. **Content behind a `BookContentExtractor` seam.** The reader serves readable
   content via an extractor interface. The only implementation this sprint,
   `PlainTextContentExtractor`, returns already-textual files (`.txt`, `.md`,
   etc.) as-is and reports everything else as `UNSUPPORTED`. This is the clean
   abstraction where a real PDF/EPUB parser will plug in later — no parsing or
   AI is introduced now.

2. **Documented temporary limitation.** Non-text files (e.g. PDF) are stored and
   listed normally but render an explicit "preview not available yet" message in
   the reader. This is an intentional, documented limitation, not a failure.

3. **Stable anchors, not page numbers.** Reading position and bookmarks are
   stored as a format-agnostic *anchor* (a character offset), preferred over
   page numbers which shift with font size and layout. The client maps the
   anchor to a scroll position; the persisted value is independent of display
   settings.

4. **Reader serves content; storage gains a `read`.** The `StorageService`
   contract gained a `read(key)` method (the only change to a prior module) so
   the reader can fetch stored bytes. Ownership is delegated to the library's
   `BookService` — the reader never bypasses it.

5. **Reads via `FutureProvider.family`, mutations via `ReaderController`.** On
   the client, content/progress/bookmarks load through family futures;
   `ReaderController` owns side-effects (save position, add/delete bookmark) and
   refreshes the relevant providers. Reader display settings are an in-memory
   `Notifier` for the session.

## Consequences

- Full reflowable reading works today for text books; PDF/EPUB await a future
  extractor implementation behind the same interface.
- Position persistence survives font/spacing changes because anchors are
  display-independent.
- The anchor↔scroll mapping is approximate (offset proportion of scroll extent);
  a precise reflow mapping can be added with the future parser without changing
  the stored anchor format.
