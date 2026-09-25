# Processing Pipeline

How an uploaded book becomes structured, readable content. No AI is involved.

```
Upload (multipart)
   │  POST /api/v1/books   (library module)
   ▼
Storage  ───────────────  raw file persisted via StorageService
   │
   ▼
ProcessingTrigger.schedule(user, book)      ← seam for future background workers
   │  (InlineProcessingTrigger today; QueuedProcessingTrigger later)
   ▼
ProcessingService.process_book
   │   1. resolve owned book (ownership enforced via library BookService)
   │   2. status → PROCESSING
   │   3. read bytes from storage
   │   4. ProcessorRegistry.select(mime, filename)  ← the dispatcher
   │   5. processor.process(...) → StructuredDocument
   │   6. persist structure + metadata
   ▼
Database  ──────────────  ProcessedBook + Chapters/Sections/Paragraphs/Sentences
   │
   ▼
status → COMPLETED   (or FAILED with a structured ProcessingErrorCode)
```

## Status lifecycle

`QUEUED → PROCESSING → COMPLETED` on success, or `→ FAILED` on error.
Only `COMPLETED` books are served by the reader.

| Code (`error_code`) | Meaning |
| --- | --- |
| `unsupported_format` | No registered processor handles the file (e.g. PDF today) |
| `malformed_file` | The file could not be parsed |
| `empty_document` | No readable text was found |
| `too_large` | The file exceeds the processing size limit |
| `timeout` | Processing exceeded its time budget |
| `internal_error` | Unexpected failure |

## Triggering & background workers

Processing is triggered from the upload route through the `ProcessingTrigger`
seam. Today it runs **inline** (synchronously) in the request. Moving to a
background worker later means providing a `QueuedProcessingTrigger` that enqueues
`process_book`; the upload route and every other caller are unchanged.

## Adding a new format

1. Implement `BookProcessor` (e.g. `PdfProcessor`) with `supports`/`process`.
2. Register it in `get_processor_registry()`.

No changes to the reader, the pipeline, the schema, or the API are required.

## Reader integration

The reader requests reconstructed text from the processing module
(`ProcessingService.get_reader_content`) — it never reads raw files. Content is
rebuilt by concatenating paragraphs in document order.
