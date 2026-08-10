# Implementation Plan

## Overview

Nine phases, 26 tasks, each independently reviewable and verifiable. Phases 1–4 are
purely additive: the Reader keeps rendering canonical text, so the branch stays
shippable until task 18, which is the single switch-over point. Every task states
what it may not break.

Backend work (tasks 1–3, 14–15) can proceed in parallel with Flutter work, and the
seam widening in task 14 is independently valuable — it fixes explanations inside
code blocks and lists before structured rendering lands.

## Task Dependency Graph

```
Backend delivery        1 ──▶ 2 ──▶ 3 ──┐
Seam widening          14 ──▶ 15        │
                                        │
Domain + data                  4 ──▶ 5 ─┴─▶ 6 ──▶ 7 ──▶ 8 ──┐
                                                             │
Composition + renderers                        9 ──▶ 10 ──▶ 11 ──▶ 13
                                               │      └──▶ 12       │
                                               │                    │
Selection                                      └──▶ 16 ──▶ 17 ──────┤
                                                                    │
Switch-over                                              18 ◀───────┘
                                                          ├──▶ 19
                                                          └──▶ 20
                                                                │
Compatibility                                        21 ◀───────┘
                                                      └──▶ 22
                                                            │
Performance                                       23 ◀──────┘
                                                   └──▶ 24
                                                         │
Verification                                  25 ◀───────┘
                                               └──▶ 26
```

Critical path: 1 → 2 → 3 → 5 → 6 → 7 → 8 → 18 → 19/20 → 21 → 23 → 25 → 26.
Task 4 has no dependencies. Tasks 9–13 depend on 7–8 only for integration, so
renderer work can start as soon as the domain model (task 4) exists.

Tasks within a wave have no dependency on each other and may run in parallel.

```json
{
  "waves": [
    { "wave": 1, "tasks": ["1", "4", "14"] },
    { "wave": 2, "tasks": ["2", "15"] },
    { "wave": 3, "tasks": ["3"] },
    { "wave": 4, "tasks": ["5"] },
    { "wave": 5, "tasks": ["6"] },
    { "wave": 6, "tasks": ["7"] },
    { "wave": 7, "tasks": ["8"] },
    { "wave": 8, "tasks": ["9"] },
    { "wave": 9, "tasks": ["10", "16"] },
    { "wave": 10, "tasks": ["11", "12", "17"] },
    { "wave": 11, "tasks": ["13"] },
    { "wave": 12, "tasks": ["18"] },
    { "wave": 13, "tasks": ["19", "20"] },
    { "wave": 14, "tasks": ["21"] },
    { "wave": 15, "tasks": ["22", "23"] },
    { "wave": 16, "tasks": ["24"] },
    { "wave": 17, "tasks": ["25"] },
    { "wave": 18, "tasks": ["26"] }
  ]
}
```

## Tasks

### Phase 1 — Backend element delivery

- [ ] 1. Add the element read model to the document store
  - **Objective:** query readable elements overlapping a canonical range, plus the structural ancestors needed to render them, without scanning the document.
  - **Files:** `apps/api/app/modules/processing/document_store.py`, `apps/api/app/modules/processing/element_query.py` (new)
  - **Components:** `DocumentStore`, new `ElementRecord` / `ElementWindow` value objects, new `DocumentElementQuery` read model
  - **Depends on:** nothing
  - **Acceptance:** overlap predicate uses `ix_document_elements_span`; ancestors resolved by parent id; `NULL`-span elements attached via parent section; ordering strictly by `sequence`; `payload` returned verbatim with no semantic interpretation; no schema, migration, codec, or write-path change.
  - **Regression risks:** accidental change to `spans_overlapping` used by the classifier; N+1 queries for ancestors.
  - **Tests:** unit tests for overlap boundaries (exactly-touching, contained, spanning), ancestor inclusion, sequence ordering, and query count bounded per window.
  - _Requirements: 6.7, 1.1, 8.2_

- [ ] 2. Enforce window bounds and truncation
  - **Objective:** guarantee a bounded response regardless of the requested range.
  - **Files:** `apps/api/app/modules/processing/element_query.py`
  - **Components:** `DocumentElementQuery`
  - **Depends on:** task 1
  - **Acceptance:** requested span clamped to 50,000 scalars; element count capped at 2,000; truncation occurs at an element boundary and never mid-parent; `truncated` flag set; caps are named constants.
  - **Regression risks:** truncation orphaning a caption or list item from its parent.
  - **Tests:** span clamping, element cap with `truncated: true`, truncation never emits a child whose parent was dropped.
  - _Requirements: 6.7, 6.1_

- [ ] 3. Expose `GET /books/{id}/content/elements`
  - **Objective:** deliver element windows to the Reader through the reader module.
  - **Files:** `apps/api/app/modules/reader/router.py`, `apps/api/app/modules/reader/schemas.py`, `apps/api/app/modules/reader/service.py`, `apps/api/app/modules/reader/dependencies.py`, `apps/api/app/modules/processing/dependencies.py`
  - **Components:** reader router, `ReaderService`, response schemas
  - **Depends on:** tasks 1–2
  - **Acceptance:** route sits beside `/content` and delegates through `ReaderService` exactly as `/content` does; ownership and 404-on-foreign-book inherited unchanged; `start`/`end` validated as non-negative with `end > start`; `text` populated only for non-derivable element text; unprocessed or failed books return an empty element set rather than an error.
  - **Regression risks:** new dependency wiring breaking existing reader routes; auth bypass on the new path.
  - **Tests:** integration tests for auth required, foreign book 404, unprocessed book empty window, response shape, and derivable text omitted.
  - _Requirements: 1.1, 6.7, 7.8, 8.1_

### Phase 2 — Flutter domain model and data layer

- [ ] 4. Model document elements in the Reader domain
  - **Objective:** a sealed, immutable element hierarchy with an explicit unknown case.
  - **Files:** `apps/mobile/lib/features/reader/domain/reader_element.dart` (new), `apps/mobile/lib/features/reader/domain/reader_span.dart` (new)
  - **Components:** `ReaderElement` sealed hierarchy, `ReaderSpan`
  - **Depends on:** nothing
  - **Acceptance:** every element type from the design is represented; `Sentence` deliberately absent; `UnknownElement` retains its raw type; all classes immutable with value equality; no format, parser, or MIME concept present anywhere.
  - **Regression risks:** none (additive).
  - **Tests:** equality and immutability; span arithmetic (intersection, emptiness, containment).
  - _Requirements: 1.1, 1.6, 2.18_

- [ ] 5. Decode element windows from the API
  - **Objective:** map API payloads to domain elements, tolerating unknown types.
  - **Files:** `apps/mobile/lib/features/reader/data/element_dto.dart` (new), `apps/mobile/lib/features/reader/data/reader_api.dart`, `apps/mobile/lib/features/reader/data/reader_repository.dart`
  - **Components:** DTOs, API client, reader repository
  - **Depends on:** tasks 3–4
  - **Acceptance:** each known type decodes to its class with payload fields mapped; unknown `type` decodes to `UnknownElement` without throwing; missing optional fields tolerated; malformed single element degrades that element only, never the window.
  - **Regression risks:** existing `/content` client path altered.
  - **Tests:** decoding per type, unknown type fallback, malformed payload isolation, window metadata (`truncated`, `character_count`).
  - _Requirements: 1.5, 1.6, 7.8_

- [ ] 6. Implement the chunked element window store
  - **Objective:** fetch, cache, and bound element residency around the reading position.
  - **Files:** `apps/mobile/lib/features/reader/domain/element_window_store.dart` (new)
  - **Components:** `ElementWindowStore`, chunk mapping, LRU
  - **Depends on:** task 5
  - **Acceptance:** chunk index is `floor(offset / 20000)` with a named constant; LRU capacity 8, oldest evicted first; a range crossing a boundary resolves from at most two chunks; concurrent requests for the same chunk coalesce into one fetch; failed fetch is not cached as empty; capacity independent of document size.
  - **Regression risks:** unbounded growth; duplicate in-flight fetches on fast page turns.
  - **Tests:** chunk mapping, eviction order, cache-hit avoids refetch, coalescing, failure not cached.
  - _Requirements: 6.1, 6.6, 6.8_

### Phase 3 — DocumentPaginationSource

- [ ] 7. Implement `DocumentOutline`
  - **Objective:** the client-side structural view over cached chunks.
  - **Files:** `apps/mobile/lib/features/reader/domain/document_outline.dart` (new)
  - **Components:** `DocumentOutline`
  - **Depends on:** task 6
  - **Acceptance:** `ensureRange` loads only the chunks covering the range; `isReady` never triggers I/O; `elementsIn` returns sequence-ordered elements intersecting the range; `readableElementAt` returns the innermost readable element containing an offset, or null; identical inputs always yield identical output ordering.
  - **Regression risks:** structural elements leaking into readable lookups.
  - **Tests:** range loading, readiness without I/O, ordering determinism, `readableElementAt` for every readable type and for gaps.
  - _Requirements: 2.1, 3.5, 4.9, 6.1_

- [ ] 8. Implement `DocumentPaginationSource`
  - **Objective:** a structure-aware source that leaves character access and measurement identical.
  - **Files:** `apps/mobile/lib/features/reader/domain/pagination_source.dart`, `apps/mobile/lib/features/reader/domain/document_pagination_source.dart` (new)
  - **Components:** `DocumentPaginationSource`, `StringPaginationSource` (composed, unmodified)
  - **Depends on:** task 7
  - **Acceptance:** implements `PaginationSource` with the interface unchanged; delegates all character access to an internal `StringPaginationSource`; exposes `outline` outside the interface; `StringPaginationSource` retained and untouched; identical offsets to `StringPaginationSource` for identical text including surrogate pairs; `PageMeasurer` and `ReadingPaginator` unmodified.
  - **Regression risks:** widening the `PaginationSource` contract; duplicating boundary-mapping logic.
  - **Tests:** Property 1 (offset equivalence, including emoji and combining marks); Property 2 (page boundaries identical to `StringPaginationSource` for the same text and key).
  - _Requirements: 7.2, 7.3, 7.5, 8.1_

### Phase 4 — Renderer registry

- [ ] 9. Build the page composer
  - **Objective:** turn a page span plus elements into an ordered, clipped block list.
  - **Files:** `apps/mobile/lib/features/reader/presentation/rendering/render_block.dart` (new), `apps/mobile/lib/features/reader/presentation/rendering/page_composer.dart` (new)
  - **Components:** `RenderBlock`, `PageComposer`
  - **Depends on:** tasks 7–8
  - **Acceptance:** each element clipped to the page span; zero-length results dropped; blocks pairwise non-overlapping and within the page span; emitted in `sequence` order; structural elements with no text emit no block; list markers numbered from the list's start number; block text taken from the canonical slice, never rebuilt from element payloads.
  - **Regression risks:** an element split across pages losing or duplicating characters.
  - **Tests:** Property 4 (coverage), Property 5 (containment), boundary-split elements, marker numbering, empty structural suppression.
  - _Requirements: 2.1, 2.2, 2.10, 2.11, 4.11_

- [ ] 10. Implement the renderer registry and deterministic spacing
  - **Objective:** extensible type-to-widget dispatch with all vertical rhythm in one place.
  - **Files:** `apps/mobile/lib/features/reader/presentation/rendering/element_renderer.dart` (new), `apps/mobile/lib/features/reader/presentation/rendering/element_renderer_registry.dart` (new), `apps/mobile/lib/features/reader/presentation/rendering/block_spacing.dart` (new), `apps/mobile/lib/features/reader/presentation/rendering/page_body.dart` (new)
  - **Components:** `ElementRenderer`, `ElementRendererRegistry`, `BlockSpacing`, `PageBody`
  - **Depends on:** task 9
  - **Acceptance:** registry resolves by first match in registration order with a body-text fallback; the Reader contains no `switch` on element type; renderers emit zero outer margin; only `PageBody` inserts gaps, between consecutive blocks only; page body does not scroll and clips overflow rather than growing.
  - **Regression risks:** doubled spacing at heading-section adjacency; page growth breaking the page frame.
  - **Tests:** Property 8 (single gap for every adjacency pair, no doubling), fallback used for unregistered types, registration order honoured, no overflow beyond page bounds.
  - _Requirements: 2.18, 1.5, 5.7, 8.1_

- [ ] 11. Implement text-element renderers
  - **Objective:** native rendering for chapter, section, paragraph, code, quote, list item, formula, caption, footnote.
  - **Files:** `apps/mobile/lib/features/reader/presentation/rendering/renderers/*.dart` (new)
  - **Components:** the nine text renderers, `ReaderTypography`
  - **Depends on:** task 10
  - **Acceptance:** chapter most prominent, section subordinate, both invisible when untitled; paragraphs visually unchanged from today; code monospaced with line breaks and leading whitespace preserved exactly and never re-indented, reformatted, tokenized, or highlighted; long code lines readable without breaking pagination; quotes visually distinct with attribution when present; list items marked bullet or sequential number; formulas verbatim and never interpreted; captions and footnotes small and de-emphasized; caption with missing target renders as body text.
  - **Regression risks:** paragraph typography drift changing the reading surface; code renderer altering whitespace.
  - **Tests:** widget test per renderer asserting the specific prohibition and the visual distinction; whitespace preservation byte-for-byte; untitled heading emits nothing.
  - _Requirements: 2.2, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.11, 2.14, 2.16, 2.17_

- [ ] 12. Implement the hyperlink renderer
  - **Objective:** tappable link text that never leaves the Reader.
  - **Files:** `apps/mobile/lib/features/reader/presentation/rendering/renderers/hyperlink_renderer.dart` (new)
  - **Components:** hyperlink renderer
  - **Depends on:** task 10
  - **Acceptance:** visually distinct and tappable; tap shows a visible acknowledgement of the target; no browser launch, no navigation, no route change, no reading interruption; link text remains selectable.
  - **Regression risks:** gesture conflict with page-turn and selection gestures.
  - **Tests:** tap shows acknowledgement, no navigator or url-launcher interaction, page turn and selection still work over link text.
  - _Requirements: 2.12, 2.13_

- [ ] 13. Implement image and table placeholder renderers
  - **Objective:** bounded, provisional placeholders that preserve reading order.
  - **Files:** `apps/mobile/lib/features/reader/presentation/rendering/renderers/image_placeholder_renderer.dart` (new), `apps/mobile/lib/features/reader/presentation/rendering/renderers/table_placeholder_renderer.dart` (new), `apps/mobile/lib/features/reader/presentation/rendering/figure_label.dart` (new)
  - **Components:** placeholder renderers, figure-label derivation
  - **Depends on:** tasks 10–11
  - **Acceptance:** image placeholder shows affordance, figure label, dimensions when known, page number when known, abbreviated identifier, and the caption when present; figure label derived from the caption's leading `Figure N` / `Table N` pattern, else generic, with parser behavior unchanged; no image byte request, decode, or cache; table placeholder identifies itself, reports row count, and renders cell text in stored row and cell order without grid, borders, alignment, or column sizing; both bounded in height and marked provisional.
  - **Regression risks:** unbounded placeholder height causing clipped or empty pages.
  - **Tests:** widget tests for each displayed field, figure-label derivation cases, zero network or storage calls during render, height bounded, no grid widgets present.
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8_

### Phase 5 — Selection resolution

- [ ] 14. Widen the explanation context seam in persistence
  - **Objective:** resolve selection context from all readable element types without touching the Explanation Engine.
  - **Files:** `apps/api/app/modules/processing/document_store.py`, `apps/api/app/modules/processing/repository.py`
  - **Components:** `DocumentStore` set-based span query, `ProcessingRepository.get_paragraphs_overlapping` seam
  - **Depends on:** nothing
  - **Acceptance:** `_CONTEXT_TYPES` contains paragraph, code block, quote, list item, footnote, formula, caption, table cell; sentence and table row excluded with the reason documented in code; the repository seam name and signature used by the classifier unchanged; no change to Explanation Engine architecture, prompts, strategies, or classification logic; sentence counting unchanged.
  - **Regression risks:** reclassifying word selections as paragraphs if sentences leak into the set; double-counting table text.
  - **Tests:** Property 11 (paragraph-only selections return results byte-identical to the paragraph-only query); spans returned for each newly included type; sentence and table row absent; existing explanation classification tests pass unchanged.
  - _Requirements: 9.1, 9.2, 9.3, 4.10_

- [ ] 15. Verify explanations resolve inside every readable element
  - **Objective:** prove Requirement 4.8 end to end at the API level.
  - **Files:** `apps/api/tests/test_explanation.py`
  - **Components:** explanation endpoint, classifier, widened seam
  - **Depends on:** task 14
  - **Acceptance:** selections inside code block, quote, list item, footnote, caption and table cell all return a successful explanation; none returns an outside-book-content error; paragraph classification outcomes unchanged.
  - **Regression risks:** none (test-only).
  - **Tests:** integration test per element type using a document containing all of them.
  - _Requirements: 4.7, 4.8, 4.2_

- [ ] 16. Implement `SelectionResolver`
  - **Objective:** map a page selection back to a canonical range, including across elements.
  - **Files:** `apps/mobile/lib/features/reader/presentation/rendering/selection_resolver.dart` (new)
  - **Components:** `SelectionResolver`, `CharacterAnchor` (unmodified)
  - **Depends on:** task 9
  - **Acceptance:** trims whitespace exactly as the current implementation; exact match preferred, duplicates disambiguated by nearest hint offset; whitespace-collapsed fallback with index mapping back to original positions; returns canonical offsets as `pageStart + scalarIndex`; returns null when unresolvable; never returns a range outside the page span.
  - **Regression risks:** wrong occurrence chosen for short repeated strings.
  - **Tests:** Property 6 (soundness), Property 7 (contiguity across adjacent elements), duplicate disambiguation, collapsed-whitespace fallback, code-block whitespace preserved, null on failure.
  - _Requirements: 4.1, 4.3, 4.4, 4.5, 4.6_

- [ ] 17. Wire page-level selection with the Explain action
  - **Objective:** one selection domain per page so selections cross element boundaries.
  - **Files:** `apps/mobile/lib/features/reader/presentation/rendering/page_body.dart`, `apps/mobile/lib/features/reader/presentation/widgets/explainable_text.dart`
  - **Components:** `SelectionArea`, context-menu Explain item, `SelectionResolver`
  - **Depends on:** tasks 16, 10
  - **Acceptance:** the page is wrapped in a single `SelectionArea`; Explain appears in the selection toolbar as today; a drag across paragraph → code block → paragraph yields one contiguous range; unresolvable selection makes Explain a no-op with no submission; `ExplainableText` retained for the canonical-text fallback path.
  - **Regression risks:** losing the Explain toolbar item; selection gestures conflicting with page turns; word-level selection regressing.
  - **Tests:** widget tests for intra-block selection parity with today, cross-block contiguity, toolbar presence, no-op on unresolvable, page turn unaffected.
  - _Requirements: 4.1, 4.2, 4.8, 8.1_

### Phase 6 — Reader integration

- [ ] 18. Switch the page body to structured rendering
  - **Objective:** replace the single canonical-text widget with composed elements, preserving all behavior.
  - **Files:** `apps/mobile/lib/features/reader/presentation/reader_screen.dart`, `apps/mobile/lib/features/reader/application/reader_providers.dart`
  - **Components:** `ReaderScreen`, `PageComposer`, registry, `DocumentPaginationSource`, `ReadingPaginator` (unmodified)
  - **Depends on:** tasks 8, 10–13, 17
  - **Acceptance:** source selected once at construction behind `PaginationSource`; no branch on format or parser anywhere; element fetching and composition run off the build phase, never inside `build()`; app bar, progress bar, footer, settings, bookmarks and explanation sheets behaviorally unchanged; page-turn interaction and gestures unchanged; theme and reader settings respected.
  - **Regression risks:** pagination or composition running in `build()`; first-page loading state regressing to a freeze; page count changing.
  - **Tests:** widget test asserting no work in `build()`, unchanged chrome, page count identical to the canonical-text reader for the same text and layout.
  - _Requirements: 1.1, 1.2, 1.4, 6.2, 6.3, 6.4, 7.3, 8.1_

- [ ] 19. Preserve progress, restore, and bookmarks
  - **Objective:** prove the anchor contract is untouched by the switch-over.
  - **Files:** `apps/mobile/lib/features/reader/presentation/reader_screen.dart`, `apps/mobile/lib/features/reader/presentation/widgets/bookmarks_sheet.dart`
  - **Components:** progress persistence, restore path, bookmark labelling
  - **Depends on:** task 18
  - **Acceptance:** position persisted and restored as a canonical scalar offset with no element id; async-late progress realigns the window; offset preserved across font, line-height, scale and viewport changes; progress percentage from offset over character count; bookmark labels derived from the readable element at the offset with a fallback to the current text scan; anchors unchanged so existing bookmarks resolve; reading-time accumulation, persist-on-turn and persist-on-dispose unchanged; page numbering still from measured pagination.
  - **Regression risks:** label derivation throwing when the outline is not loaded; restore racing the first window.
  - **Tests:** Property 3 (anchor round trip), late-progress realignment, offset preserved across a font change, bookmark create-label-jump for a non-paragraph element, legacy bookmark resolution.
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10, 3.11_

- [ ] 20. Implement caching and prefetch
  - **Objective:** make repeated rebuilds free and page turns instant.
  - **Files:** `apps/mobile/lib/features/reader/presentation/rendering/page_composer.dart`, `apps/mobile/lib/features/reader/presentation/reader_screen.dart`
  - **Components:** composed-block LRU, chunk prefetch, `PaginationKey` invalidation
  - **Depends on:** task 18
  - **Acceptance:** composed blocks cached by page index, `PaginationKey` and chunk generation, LRU about 12 pages; element chunks survive typography changes; only measured pages and composed blocks rebuild on a layout change; one chunk and two pages prefetched ahead; a rebuild with no layout change performs no fetch, no re-map and no re-measure.
  - **Regression risks:** stale blocks after a chunk arrives; cache key missing a layout input.
  - **Tests:** Property 9 (determinism across cold builds), Property 10 (boundedness), no-op rebuild performs zero work, chunk arrival invalidates affected pages only.
  - _Requirements: 6.6, 6.1, 6.2_

### Phase 7 — Backward compatibility

- [ ] 21. Implement and verify canonical-text degradation
  - **Objective:** guarantee no element-layer failure can prevent reading.
  - **Files:** `apps/mobile/lib/features/reader/presentation/reader_screen.dart`, `apps/mobile/lib/features/reader/domain/element_window_store.dart`
  - **Components:** degradation path, `StringPaginationSource`, `ExplainableText`
  - **Depends on:** tasks 18–20
  - **Acceptance:** element endpoint failure or timeout renders the window as canonical body text and retries on the next window; a book with no stored structure uses `StringPaginationSource` with exactly today's behavior; unknown and malformed elements degrade to body text; unsupported-format and processing-failure views unchanged; progress, bookmarks and explanations work in every degraded mode.
  - **Regression risks:** degradation loop retrying every frame; silent permanent degradation after one transient failure.
  - **Tests:** Property 12 (degradation totality) across each failure mode; retry bounded; legacy structureless book reads.
  - _Requirements: 7.1, 7.6, 7.7, 7.8, 1.6_

- [ ] 22. Verify format parity across TXT, PDF and legacy books
  - **Objective:** prove the Reader is format-agnostic in behavior, not just in code.
  - **Files:** `apps/mobile/test/features/reader/*`, `apps/api/tests/test_processing_api.py`
  - **Components:** full reading path for both parsers
  - **Depends on:** task 21
  - **Acceptance:** a TXT book and a PDF book with equivalent structure render identical block sequences; gestures, progress semantics, selection semantics and settings identical; no parser or format identity displayed; a static check confirms no format, MIME, extension or parser identifier appears in Reader code.
  - **Regression risks:** TXT-specific shortcuts creeping into rendering.
  - **Tests:** parity test over equivalent documents, grep-style guard test for format identifiers in the reader feature.
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 7.5, 7.6_

### Phase 8 — Performance

- [ ] 23. Benchmark the three reference documents
  - **Objective:** measure against the stated targets and record the results.
  - **Files:** `apps/mobile/test/features/reader/reader_benchmark_test.dart` (new), sprint report
  - **Components:** window store, composer, paginator, page body
  - **Depends on:** tasks 20–21
  - **Acceptance:** small TXT, medium PDF and the 911-page SQL reference PDF measured for time to first readable page (≤ 200 ms small, ≤ 500 ms reference), median frame budget ≤ 16 ms with no frame over 32 ms attributable to reader work, peak memory ≤ 1.3× the canonical-text baseline, resident element records ≤ 3,000, and no dropped frames over 50 sustained turns; figures recorded in the sprint report.
  - **Regression risks:** benchmark passing on a small document while the reference book regresses.
  - **Tests:** composition and window microbenchmarks in CI; device measurement on the POCO X2 recorded manually.
  - _Requirements: 6.4, 6.5, 6.8, 6.9_

- [ ] 24. Close any performance gap found
  - **Objective:** fix regressions the benchmark exposes without changing architecture.
  - **Files:** as indicated by measurement
  - **Components:** as indicated by measurement
  - **Depends on:** task 23
  - **Acceptance:** all targets in task 23 met; no fix introduces work in `build()`, whole-document traversal, or an unbounded cache; chunk size, LRU capacities and prefetch depth remain named constants.
  - **Regression risks:** tuning constants to pass one document while harming another.
  - **Tests:** re-run task 23 for all three documents.
  - _Requirements: 6.1, 6.2, 6.3, 6.5, 6.8_

### Phase 9 — Test completion and traceability

- [ ] 25. Complete requirement-to-test traceability
  - **Objective:** every requirement covered by at least one automated test.
  - **Files:** `apps/api/tests/*`, `apps/mobile/test/features/reader/*`, sprint report
  - **Components:** whole feature
  - **Depends on:** tasks 1–24
  - **Acceptance:** a traceability table maps every requirement in requirements.md to at least one named test, with benchmark figures recorded rather than asserted; all twelve correctness properties have a test; full backend and Flutter suites pass; changed assertions are individually justified as intended behavior changes.
  - **Regression risks:** requirements silently uncovered; assertions weakened to pass.
  - **Tests:** the traceability table itself, reviewed against requirements.md.
  - _Requirements: 8.3, 8.4_

- [ ] 26. Verify the no-regression contract
  - **Objective:** confirm nothing outside the Reader integration seam changed.
  - **Files:** review only
  - **Components:** parser, Document Model, persistence schema, Explanation Engine, LIE
  - **Depends on:** task 25
  - **Acceptance:** a diff review shows no change to parser behavior, Document Model, persistence schema or migrations, Explanation Engine architecture, prompts, strategies or classification logic, or the LIE; the only backend behavior change is the widened context seam; pixel-level visual differences accepted, behavioral differences documented and justified.
  - **Regression risks:** incidental edits to completed sprints.
  - **Tests:** full suites plus the diff review checklist.
  - _Requirements: 8.1, 8.2, 8.3, 9.2_

## Implementation roadmap

| Phase | Tasks | Outcome | Reader affected |
| --- | --- | --- | --- |
| 1 | 1–3 | Element windows available over HTTP | No |
| 2 | 4–6 | Elements decoded and cached client-side | No |
| 3 | 7–8 | Structure-aware source behind the existing abstraction | No |
| 4 | 9–13 | Renderers exist and are unit-tested in isolation | No |
| 5 | 14–17 | Selection resolves across elements; seam widened | Partly |
| 6 | 18–20 | Switch-over: structured rendering live | Yes |
| 7 | 21–22 | Degradation and format parity proven | Yes |
| 8 | 23–24 | Performance measured and met | Yes |
| 9 | 25–26 | Traceability and no-regression verified | No |

Phases 1–4 are additive: the Reader keeps rendering canonical text throughout, so
the branch stays shippable until task 18. Task 14 can proceed in parallel with the
Flutter work, since it is backend-only and independently valuable — it fixes
explanations in code and lists even before structured rendering lands.

## Estimated implementation order

1. Tasks 1–3 (backend delivery), then 14–15 (seam widening) — backend complete and independently verifiable.
2. Tasks 4–6 (domain and data), then 7–8 (source) — client capability without UI change.
3. Tasks 9–13 (composition and renderers), then 16–17 (selection) — testable in isolation via widget tests.
4. Task 18 (switch-over), immediately followed by 19–20 — never leave the switch-over without progress preservation and caching.
5. Tasks 21–22 (compatibility), 23–24 (performance), 25–26 (verification).

## Expected risks

| Risk | Severity | Mitigation |
| --- | --- | --- |
| Rendered height exceeds measured height, so pages under- or over-fill | High | Compact spacing table, clip not grow, page-fill assertions on the reference book; structure-aware measurement deferred to 6.6 as a documented limitation |
| Selection resolves to the wrong occurrence of a short repeated string | Medium | Hint-nearest disambiguation, null rather than guess, explicit tests |
| Seam widening reclassifies word selections as paragraphs | High | Sentence and table row excluded; Property 11 asserts byte-identical paragraph results |
| Element fetch latency stutters page turns | Medium | Prefetch one chunk and two pages ahead; fetch off the critical path; degradation renders canonical text meanwhile |
| Memory growth on the reference book | Medium | LRU bounds on chunks and composed blocks; Property 10 test; benchmark gate |
| Doubled spacing between heading and section | Low | Renderers emit zero margin; single spacing owner; adjacency-pair tests |
| Incidental edits to completed sprints | Medium | Task 26 diff review; parser and Document Model treated as frozen |

## Rollback strategy

The design makes rollback cheap because the substrate never changes.

- **Per-window rollback (runtime, automatic).** Any element-layer failure degrades that window to canonical text. No user action, no data change.
- **Feature-level rollback (one construction site).** Reverting the source selection in task 18 to `StringPaginationSource` plus `ExplainableText` restores the pre-sprint Reader exactly. Nothing downstream branches on the choice.
- **Phase-level rollback.** Phases 1–5 are additive; reverting phase 6 alone leaves the backend endpoint and Flutter models in place, unused and harmless.
- **Data rollback.** None required. No schema change, no migration, no anchor format change, no reprocessing. Positions and bookmarks written during the sprint remain valid after a full revert.
- **Backend seam rollback.** Task 14 is a single frozen set; reverting it to `{PARAGRAPH}` restores prior classification exactly, at the cost of Requirement 4.8.

## Validation checklist

- [ ] Element window endpoint enforces span and element caps, and reports truncation
- [ ] No Reader code path references format, MIME type, extension or parser
- [ ] `StringPaginationSource` retained, functional, and composed by `DocumentPaginationSource`
- [ ] Offsets identical across both sources, including surrogate pairs
- [ ] Page boundaries unchanged from Sprint 6.1 for the same text and layout
- [ ] All thirteen element types render natively; unknown types render as body text
- [ ] Renderers emit zero outer margin; spacing has exactly one owner
- [ ] Code whitespace and line breaks preserved byte-for-byte; no highlighting
- [ ] Formulas verbatim; hyperlinks tappable without navigation
- [ ] Image and table placeholders bounded, provisional, and free of byte fetches
- [ ] Figure label shown when derivable from the caption
- [ ] Progress and bookmarks persist as canonical scalar offsets only
- [ ] Legacy positions and bookmarks resolve without migration
- [ ] Offset preserved across typography and viewport changes
- [ ] Selections resolve inside paragraph, code, quote, list item, formula, caption, footnote and table cell
- [ ] Cross-element selections resolve to one contiguous range
- [ ] Explanation Engine architecture, prompts, strategies and classification unchanged
- [ ] Degradation to canonical text verified for every element-layer failure mode
- [ ] TXT, PDF and legacy books behave identically
- [ ] Benchmarks met and recorded for all three documents
- [ ] All twelve correctness properties have tests
- [ ] Every requirement maps to at least one automated test
- [ ] Full backend and Flutter suites pass; changed assertions justified

## Notes

- Chunk size (20,000 scalars), LRU capacities (8 chunks, ~12 pages), prefetch depth
  (1 chunk, 2 pages), and response caps (50,000 scalars, 2,000 elements) are named
  constants, tunable in task 24 without architectural change.
- Sprint 6.6 items explicitly excluded here: rich image rendering, real table
  layout, syntax highlighting, inline run styling, chapter-start pagination,
  structure-aware measurement, hyperlink navigation, and footnote linking.

## Definition of Done for Sprint 6.5

1. The Reader renders the Document Model natively for every element type, with image and table placeholders, and never inspects format or parser.
2. `DocumentPaginationSource` is live behind the unchanged `PaginationSource` abstraction, with `StringPaginationSource` retained and exercised by the degradation path.
3. Canonical scalar offsets remain the only persisted anchor; progress, restore and bookmarks behave exactly as before, including for positions saved before the sprint.
4. Selections resolve correctly inside every readable element type and across adjacent elements, with the Explanation Engine untouched and the widening confined to the persistence seam.
5. Rendering is deterministic: identical inputs produce identical block sequences and page boundaries across launches, with a single owner of inter-block spacing.
6. Benchmarks on the small TXT book, medium PDF book and 911-page SQL reference PDF meet the stated targets and are recorded.
7. No element-layer failure can prevent reading; every failure mode degrades to canonical text.
8. Parser, Document Model, persistence schema, Explanation Engine and LIE are unmodified; the only backend behavior change is the widened context seam.
9. Every requirement maps to at least one automated test; all twelve correctness properties are tested; full suites pass with any changed assertion justified.
10. Sprint 6.6 needs no Reader redesign: rich images, real tables, inline runs and chapter-start pagination each land on a named extension point.
