# ADR 0007 — Book Processing Engine

- **Status:** Accepted
- **Date:** Sprint 3.5

## Context

ReadMe.ai must never operate on raw PDFs/files directly. Every book should
become a **structured internal document** that powers the reader today and
highlighting, selection, notes, search, citations, and AI features later — all
of which need stable addressing and structure, not flat text. This engine is
strictly non-AI.

## Decisions

1. **Processor interface + registry (dispatcher).** A `BookProcessor` protocol
   (`supports`, `process`) with a `ProcessorRegistry` that selects by MIME/
   extension. The reader and service depend only on the interface, so PDF, EPUB,
   DOCX, and OCR processors are added by registering one class — nothing else
   changes (ADR 0003 principle).

2. **Only `PlainTextProcessor` is implemented.** Per the engineering rule, PDF
   parsing (a heavy dependency) is **not** implemented; it is a documented
   extension point. Unsupported formats are recorded as a structured
   `unsupported_format` failure.

3. **Structured document model.** Document → Chapter → Section → Paragraph →
   Sentence. Text is stored **once**, on `Paragraph`; sentences and higher levels
   carry only character offsets into a canonical document text. This avoids
   duplication and keeps sentence/word addressing available for future
   selection/highlighting.

4. **Stable anchors, never page numbers.** Every structural row gets a
   deterministic anchor (`ch1`, `ch1-sec2`, `ch1-sec2-p3`, `ch1-sec2-p3-s1`),
   stable across reprocessing of identical structure. Future bookmarks, notes,
   highlights, and citations address content by these anchors.

5. **Denormalised parent reference for read efficiency.** Each structural row
   also stores `processed_book_id`, so the reader reconstructs a document with a
   single indexed, ordered query over paragraphs rather than walking the
   hierarchy — important for very large books.

6. **Pipeline with a trigger seam for future workers.** Upload → storage →
   `ProcessingTrigger.schedule` → `ProcessingService.process_book` (select →
   parse → persist) → status. Today `InlineProcessingTrigger` runs synchronously
   in the upload request; a `QueuedProcessingTrigger` can enqueue for a worker
   later with **no change at the call site**. Status: `QUEUED → PROCESSING →
   COMPLETED | FAILED`.

7. **Reader consumes structured content.** The reader no longer reads raw files
   or extracts text itself; `ReaderService` asks the processing module for the
   reconstructed text and renders only `COMPLETED` books. The reader's old
   extractor was removed.

8. **Failures are structured and never break upload.** Processing catches
   expected errors (unsupported, malformed, empty, too-large) and records a
   `ProcessingErrorCode`; the upload still succeeds and the book's processing
   status reflects the outcome.

## Consequences

- Text books are fully structured and readable today; other formats are stored
  and reported as unsupported until their processor is added.
- The library `Book.status` is left unchanged (upload-level state); processing
  state lives in `ProcessedBook.status`, keeping the library module untouched
  except for the one-line trigger call in the upload route.
- Reprocessing clears structural rows explicitly (FK-safe order) for identical
  behaviour on SQLite and PostgreSQL.
