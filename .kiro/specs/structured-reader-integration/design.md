# Design Document

## Overview

The Reader stops treating a book as one string and starts treating it as ordered,
typed elements — without changing the reading experience, the page-turn
interaction, the pagination algorithm, the parser, or the Explanation Engine.

The central design decision is this: **canonical text remains the coordinate
space; structure changes only presentation.**

Pagination continues to measure canonical text through the Sprint 6.1 paginator,
so page boundaries, anchors, progress, and bookmarks are untouched by definition.
Elements are fetched in windows and used to decide *how* the characters on a page
are rendered — a heading, a code block, a list item, a placeholder — never *which*
characters exist or where they sit. Selection stays expressed as canonical scalar
offsets, so the Explanation Engine sees exactly the contract it sees today.

This is what makes the migration provably non-destructive. If element delivery
fails entirely, the Reader renders canonical text and every feature still works.
Structure is an enhancement layer over an unchanged substrate.

### Design goals

1. **Reader-first.** Reading fluency outranks structural fidelity everywhere.
2. **Format agnostic.** No Reader code path may observe format or parser.
3. **Canonical offsets only.** The sole persisted anchor format, unchanged.
4. **Document Model as single source of truth.** Rendering derives from stored
   elements, never from re-parsing or client-side inference.
5. **Rendering determinism.** Given the same document, viewport, typography and
   settings, pagination and render order are identical across launches — a
   prerequisite for future highlights, annotations, and sync.
6. **Open/Closed.** New element types and richer renderers register; the Reader
   does not change.
7. **Bounded work.** Memory and per-frame cost are proportional to the reading
   window, never the document.

### Non-goals

Image bytes, real table layout, hyperlink navigation, inline run styling within a
sentence, chapter-start page breaks, UI redesign, and pagination redesign.

### Regression policy

Pixel-level visual refinement is acceptable and expected — headings and code
blocks now occupy different space than flat text did. Behavioral regression is
not: gestures, progress semantics, selection semantics, bookmark resolution, and
explanation outcomes must be preserved.

## Architecture

### Layered view

```
Backend (unchanged storage)
  documents (canonical text)  document_elements (typed, spanned)
        │                              │
        │  GET /content                │  GET /content/elements?start&end
        ▼                              ▼
Flutter data layer
  BookContent (text)            ElementWindow (typed element records)
        │                              │
        └──────────┬───────────────────┘
                   ▼
Flutter domain layer
  DocumentPaginationSource  ──implements──▶  PaginationSource
  DocumentOutline (window cache, canonical spans)
                   │
                   ▼
Presentation
  ReadingPaginator (unchanged)  ──▶ DocumentPage (canonical span + text)
                   │
                   ▼
  PageComposer  ──▶ RenderBlock[]  ──▶ ElementRendererRegistry ──▶ widgets
                   │
                   ▼
  SelectionArea + SelectionResolver ──▶ canonical [start,end) ──▶ ExplanationSheet
```

Every arrow points one way. The paginator never sees an element; renderers never
see a parser; the Explanation Engine never sees a widget.

### What changes and what does not

| Component | Status |
| --- | --- |
| `PaginationSource`, `PageMeasurer`, `ReadingPaginator`, `DocumentPage`, `PaginationKey` | Unchanged |
| `StringPaginationSource` | Retained, still used for degradation |
| `CharacterAnchor` | Unchanged |
| `ReaderScreen` chrome, `PageTurnView`, settings, bookmarks sheet, explanation sheet | Behaviorally unchanged |
| Parser, Document Model, `document_store` schema, migrations | Unmodified |
| Explanation Engine strategies, prompts, classifier logic | Unmodified |
| Page body rendering | Replaced: one `ExplainableText` becomes composed element widgets |
| Selection capture | Replaced: per-widget selection becomes page-level `SelectionArea` |
| Element delivery | New: endpoint, read model, Flutter models, window cache |
| Explanation context seam | Widened inside persistence (Requirement 9) |

## Components and Interfaces

### 1. Backend element read model

A read model in the processing module, beside the existing store. `DocumentStore`
gains query methods; its schema, write path, and codec are untouched.

```python
@dataclass(frozen=True, slots=True)
class ElementRecord:
    element_id: str
    parent_id: str | None
    element_type: str
    order_index: int
    sequence: int
    start_offset: int | None
    end_offset: int | None
    page_number: int | None
    payload: dict[str, JsonValue]      # type-specific fields, verbatim
    text: str | None                   # inline text for elements that carry it

@dataclass(frozen=True, slots=True)
class ElementWindow:
    start: int
    end: int
    character_count: int
    elements: tuple[ElementRecord, ...]
    truncated: bool
```

Retrieval predicate, for a requested canonical range `[start, end)`:

- readable elements whose span **overlaps** the range (`start_offset < end AND
  end_offset > start`) — served by the existing
  `ix_document_elements_span` index;
- structural ancestors of those elements (chapter, section, list, table, image),
  fetched by parent id so a page never renders an orphaned list item or a caption
  without its image;
- elements with `NULL` spans (hyperlinks) attached via their parent section.

Ordering is `(sequence)`, the storage order the parser produced — deterministic
and identical to document order.

`payload` is passed through as stored. The backend does not interpret element
semantics, which is what keeps the API parser-agnostic and future-proof: a new
element type flows to the client without a backend change.

### 2. Element delivery API

```
GET /api/v1/books/{book_id}/content/elements?start={int}&end={int}
```

Placed beside `GET /content` in the reader router and delegated through
`ReaderService` to the processing read model, exactly as `/content` already
delegates to `ProcessingService`. Ownership, auth, and the 404-on-foreign-book
behavior are inherited unchanged.

Response:

```json
{
  "book_id": "…",
  "start": 0,
  "end": 20000,
  "character_count": 2091963,
  "truncated": false,
  "elements": [
    {
      "id": "…", "parent_id": "…", "type": "paragraph",
      "order_index": 0, "sequence": 12,
      "start_offset": 480, "end_offset": 1220,
      "page_number": 14,
      "payload": {},
      "text": null
    }
  ]
}
```

Bounds, so a response can never be unbounded (Requirement 6.7):

| Guard | Value | Behavior on breach |
| --- | --- | --- |
| Max requested span | 50,000 scalars | Span clamped |
| Max elements per response | 2,000 | Truncated at an element boundary, `truncated: true` |

`text` is populated only for elements whose text is not derivable from the
canonical slice the client already holds (captions with styled runs, table cells,
hyperlink labels). Paragraph, code, quote, list-item, footnote and formula text is
derived client-side from the canonical text by span — no duplication over the
wire, matching the storage-level rule from Sprint 6.3.5.

### 3. Windowed retrieval strategy

Windows are **fixed canonical-offset chunks**, not arbitrary ranges:

```
chunkIndex = floor(offset / 20000)
chunkRange = [chunkIndex * 20000, (chunkIndex + 1) * 20000)
```

Fixed chunks give three properties an arbitrary-range fetch cannot: cache keys are
stable and deterministic, a page crossing a boundary needs at most two chunks, and
prefetch targets are predictable. Chunk size is a named constant; 20,000 scalars is
roughly 8–12 pages of body text, so a chunk covers the reading window plus
look-ahead.

`ElementWindowStore` (Flutter) holds an LRU of chunks, default capacity 8. Peak
element residency is therefore bounded at roughly 8 chunks — on the reference book
about 2,000–3,000 element records regardless of the book's 51,500 total, satisfying
Requirement 6.8.

Fetches are triggered off the build phase, from the same post-frame path that
drives pagination, and are prefetched one chunk ahead of the current offset.

### 4. `DocumentPaginationSource`

```dart
class DocumentPaginationSource implements PaginationSource {
  DocumentPaginationSource({
    required String canonicalText,
    required DocumentOutline outline,
  });

  // PaginationSource — delegated to an internal StringPaginationSource.
  int get length;
  String scalarSubstring(int start, int end);
  String scalarAt(int index);

  // Structure access, used by the composer only.
  DocumentOutline get outline;
}
```

Three deliberate decisions:

**It composes `StringPaginationSource` rather than reimplementing character
access.** One boundary-mapping implementation exists, so both sources produce
byte-identical canonical offsets for identical text — Requirement 7.5 holds by
construction, not by test agreement.

**It does not change measurement.** `PageMeasurer` receives the same interface and
behaves identically, so page boundaries for a given text and layout are unchanged
from Sprint 6.1. This is why progress and bookmarks need no migration.

**Structure is exposed outside the `PaginationSource` interface.** The paginator
depends only on the three-method abstraction (Requirement 7.3); the composer
reaches structure through `outline`, a separate collaborator. Adding structure did
not widen the pagination contract.

`DocumentOutline` is the client-side view over cached chunks:

```dart
class DocumentOutline {
  Future<void> ensureRange(int start, int end);          // chunk fetch + cache
  bool isReady(int start, int end);
  List<ReaderElement> elementsIn(int start, int end);     // sorted by sequence
  ReaderElement? readableElementAt(int offset);           // whole-passage explain
}
```

### 5. Flutter domain model

A sealed hierarchy mirroring the Document Model vocabulary, immutable, with an
explicit unknown case:

```dart
sealed class ReaderElement {
  String get id;
  String? get parentId;
  int get orderIndex;
  int get sequence;
  ReaderSpan? get span;        // canonical [start, end)
  int? get pageNumber;
}

final class ChapterElement    extends ReaderElement { String? title; }
final class SectionElement    extends ReaderElement { String? title; }
final class ParagraphElement  extends ReaderElement {}
final class CodeBlockElement  extends ReaderElement { String? language; }
final class QuoteElement      extends ReaderElement { String? attribution; }
final class ListElement       extends ReaderElement { bool ordered; int? startNumber; }
final class ListItemElement   extends ReaderElement {}
final class HyperlinkElement  extends ReaderElement { String target; String label; }
final class FormulaElement    extends ReaderElement { String representation; }
final class ImageElement      extends ReaderElement {
  String identifier; double? width; double? height;
  String? mediaType; String? captionId;
}
final class CaptionElement    extends ReaderElement { String describesId; String? text; }
final class TableElement      extends ReaderElement { int rowCount; }
final class TableRowElement   extends ReaderElement {}
final class TableCellElement  extends ReaderElement { bool isHeader; String? text; }
final class FootnoteElement   extends ReaderElement { String? label; }
final class UnknownElement    extends ReaderElement { String rawType; }
```

Decoding an unrecognised `type` yields `UnknownElement`, which renders as body text
from its span (Requirement 1.6). The Reader never crashes on a future element type,
and Sprint 6.6+ parsers can ship ahead of Reader support.

`Sentence` is intentionally absent: sentences are sub-spans of paragraphs and carry
no independent presentation. Excluding them keeps element volume down and avoids
double-rendering.

### 6. Rendering pipeline

Three stages, each independently testable, none of them touching Flutter layout
policy more than once.

**Stage 1 — `PageComposer`: page span + elements → `RenderBlock[]`.**

```dart
@immutable
class RenderBlock {
  final ReaderElement element;
  final ReaderSpan visibleSpan;   // element span ∩ page span
  final String text;              // canonical slice for visibleSpan
  final int depth;                // list nesting
  final int? marker;              // ordered-list number
}
```

The composer clips each element to the page span, so an element split across a page
boundary renders its visible part on each page with correct offsets, and drops
zero-length results. Structural elements with no text (untitled chapter, list
container, table container) produce no block, satisfying Requirements 2.2 and 4.11.
Blocks are emitted in `sequence` order — deterministic.

**Stage 2 — `ElementRendererRegistry`: block → widget.**

```dart
abstract class ElementRenderer {
  bool handles(ReaderElement element);
  Widget build(BuildContext context, RenderBlock block, ReaderTypography type);
}

class ElementRendererRegistry {
  void register(ElementRenderer renderer);   // first match wins, ordered
  Widget render(BuildContext context, RenderBlock block, ReaderTypography type);
}
```

Registered renderers: chapter heading, section heading, paragraph, code block,
quote, list item, hyperlink, formula, image placeholder, caption, table
placeholder, footnote, and a fallback body-text renderer used for
`UnknownElement` and for any block no renderer claims. Registration order is the
extension seam: Sprint 6.6 registers a real image renderer ahead of the
placeholder and nothing else changes.

**Stage 3 — `PageBody`: widget list → laid-out page.**

A single non-scrolling `Column` inside the existing page frame, wrapped in one
`SelectionArea`.

**Deterministic spacing.** This is a rule, not a convention: *renderers emit zero
outer margin*. All vertical rhythm comes from one `BlockSpacing` function owned by
`PageBody`:

```dart
double gapBetween(ReaderElementKind previous, ReaderElementKind next);
```

Spacing is inserted by `PageBody` between consecutive blocks only. Because exactly
one component contributes vertical space, heading and section gaps cannot
accidentally double when a heading follows a section, and the same block sequence
always produces the same height — which is what makes measurement and pagination
reproducible across launches.

**Measurement fidelity caveat.** `PageMeasurer` measures the page's canonical slice
with body typography, while the composed page renders headings larger and code in a
monospaced face. Rendered height can therefore exceed measured height. The mitigation
is bounded and explicit: `PageBody` clips overflow rather than growing the page, the
spacing table is tuned so structural chrome is compact, and page fill is verified in
tests against the reference book. Making the measurer structure-aware would change
pagination and page counts, which this sprint forbids; that is a Sprint 6.6 item and
is listed as a known limitation.

### 7. Selection resolution pipeline

Cross-element selection (Paragraph → CodeBlock → Paragraph) requires one selection
domain per page, so the page is wrapped in a single `SelectionArea` with the
existing "Explain" context-menu action. Per-widget `SelectableText` would truncate
selections at element boundaries, which Requirement 4 forbids.

`SelectionArea` reports selected *text*, not offsets. Resolution therefore maps text
back to canonical offsets against the page's own canonical slice:

```dart
class SelectionResolver {
  ReaderSpan? resolve({
    required String pageText,        // canonical slice for the page
    required int pageStartOffset,    // canonical start of the page
    required String selectedText,
    required int? hintOffset,        // last known caret/anchor, may be null
  });
}
```

Algorithm:

1. Trim leading and trailing whitespace from the selection, exactly as the current
   implementation does, so submitted text matches today's behavior.
2. Search `pageText` for the trimmed selection. Multiple hits are disambiguated by
   choosing the occurrence nearest `hintOffset`.
3. If no exact hit — the case where rendering inserted or omitted separator
   whitespace between blocks — retry on whitespace-collapsed forms of both strings,
   keeping an index map back to original positions, and return the mapped span.
4. Convert the match to canonical offsets as `pageStartOffset + scalarIndex`, using
   `CharacterAnchor` for UTF-16 to scalar conversion.
5. Return `null` when nothing resolves; the Explain action is then a no-op rather
   than submitting a wrong range.

This works because the page's canonical slice is a superset of every character
rendered on that page: composition only clips and re-styles, never rewrites. Code
blocks keep their internal whitespace, so Requirement 4.3 is satisfied by the
canonical slice itself.

Cross-element selections resolve to one contiguous canonical range spanning the
intervening separator characters. That is intentional: the range is contiguous in
canonical space, which is exactly what the Explanation Engine expects, and the
classifier will see multiple overlapping context elements and classify it as a
passage.

The whole-passage Explain action asks `DocumentOutline.readableElementAt(offset)`
for the element containing the current position and submits its span, whatever its
type — replacing today's blank-line paragraph scan and satisfying Requirement 4.9.

### 8. Explanation integration and seam widening

The Explanation Engine, its prompts, strategies, and classifier are untouched. The
widening happens in the persistence seam it already calls.

Today `DocumentStore.spans_overlapping` takes a single `ElementType`, and
`ProcessingRepository.get_paragraphs_overlapping` passes `PARAGRAPH`. The store
gains a set-based query, and the repository method — the seam name the classifier
calls — delegates to it:

```python
_CONTEXT_TYPES = frozenset({
    ElementType.PARAGRAPH, ElementType.CODE_BLOCK, ElementType.QUOTE,
    ElementType.LIST_ITEM, ElementType.FOOTNOTE, ElementType.FORMULA,
    ElementType.CAPTION, ElementType.TABLE_CELL,
})
```

The membership of that set is the whole design decision, and two exclusions matter:

- **`SENTENCE` is excluded.** Sentences nest inside paragraphs. Including them
  would make a single word selection return two overlapping spans, and the
  classifier — which reads "more than one span" as a passage — would reclassify
  every word as a paragraph. Excluding them is what keeps Requirement 9.3 true.
- **`TABLE_ROW` is excluded.** A row's span is the union of its cells; including
  both would double-count the same characters.

The remaining types are non-overlapping siblings in canonical space, so span count
keeps the meaning the classifier already assigns it. For selections that touch only
paragraphs, the result set is identical to today's, character for character.

Sentence counting for word-versus-sentence classification is unchanged. A selection
inside a code block yields zero sentence rows and classifies as a word or sentence
by word count, which is correct behavior for code and requires no classifier change.

### 9. Reading progress and bookmark preservation

Nothing in the persistence contract changes, because nothing needs to.

- Position is a canonical scalar offset string, as today. Element IDs are not
  persisted (Requirement 3.1, 3.2).
- Page boundaries are produced by the same measurer over the same canonical text,
  so a saved offset resolves to the same page as before.
- Restore, async-progress realignment, persist-on-turn, persist-on-dispose, and
  reading-time accumulation keep their current implementations.
- Progress percentage stays `offset / characterCount`.
- Font, line-height, scale, and viewport changes rebuild the paginator under a new
  `PaginationKey` while the offset is preserved and the window realigned — the
  existing Sprint 6.1 behavior.

Bookmark labels are the one improvement: instead of scanning for `\n\n`
boundaries, the label comes from the readable element at the offset via
`DocumentOutline`, so a bookmark inside a code block or list item gets a meaningful
label (Requirement 3.5). Anchors are unchanged, so existing bookmarks resolve
untouched. When the outline is not loaded, label derivation falls back to today's
text scan.

### 10. Image and table placeholders

The image placeholder is a bounded card showing an image affordance, a figure
label, dimensions when known, page number when known, and the caption when
present. No byte fetch of any kind.

Figure label resolution, in order: the leading `Figure N` / `Table N` pattern of the
attached caption; otherwise `Figure` with no number; and the abbreviated identifier
(`sha256:1a2b3c…`) shown as secondary detail. The label is derived in the Reader
from data the parser already produced — parser behavior does not change.

The table placeholder is a bounded card identifying itself as a table, reporting
row count, and rendering its cell text in canonical row-and-cell order as plain
lines. No grid, no borders, no column sizing, no alignment inference.

Both are visually marked provisional and are bounded in height so they cannot
overflow a page or leave one blank.

### 11. Caching strategy

| Cache | Key | Bound | Invalidated by |
| --- | --- | --- | --- |
| Canonical text | book id | 1 book | Book change |
| Element chunks | (book id, chunk index) | LRU 8 chunks | Book change; never by layout |
| Measured pages | `PaginationKey` | Existing paginator behavior | Typography, viewport, scale, direction, locale |
| Composed blocks | (page index, `PaginationKey`, chunk generation) | LRU ~12 pages | Page re-measure, chunk arrival |

The separation matters: element chunks survive font-size changes, because structure
is independent of layout. Only measured pages and composed blocks are rebuilt.
Repeated widget rebuilds hit all four caches and recompute nothing (Requirement
6.6).

### 12. Performance strategy and benchmark targets

Mechanisms: canonical text loaded once as today; elements windowed and LRU-bounded;
all fetching and measurement off the build phase; prefetch one chunk and two pages
ahead; composition per page, cached; no whole-document traversal on client or
server.

Benchmarks on the reference book — the 911-page SQL PDF (~2.1M characters, ~51,500
elements) — plus a small TXT book and a medium PDF book:

| Metric | Target |
| --- | --- |
| Time to first readable page, reference book | ≤ 500 ms after content resolves |
| Time to first readable page, small TXT | ≤ 200 ms |
| Page turn, median frame budget | ≤ 16 ms; no frame > 32 ms attributable to reader work |
| Element chunk fetch | Off the critical path; never blocks a turn |
| Peak memory, reference book | ≤ 1.3× the canonical-text baseline for the same book |
| Resident element records | ≤ 3,000 regardless of document size |
| Jank during sustained turning (50 pages) | No dropped frames attributable to element loading, mapping, or measurement |

Measured with Flutter timeline/frame statistics on the physical POCO X2 and via
widget-level microbenchmarks for composition.

### 13. Error handling

| Condition | Behavior |
| --- | --- |
| Element endpoint fails or times out | Render the window as canonical body text; retry on next window; reading never blocked |
| Structure absent (pre-6.3.5 book, failed parse) | `StringPaginationSource` path, current behavior exactly |
| Unknown element type | `UnknownElement` → body text from span |
| Malformed element payload | Element degraded to body text; window still rendered |
| Caption whose target is missing | Rendered as ordinary body text |
| Image or table element with no span | Placeholder rendered, contributes no selectable range |
| Selection unresolvable | Explain action is a no-op; no wrong range submitted |
| Book not processed / unsupported / failed | Existing unsupported and error views, unchanged |
| Foreign or missing book | Existing 404 semantics from `BookService` |

The governing rule: **no element-layer failure may prevent reading.** Every path
above degrades toward canonical text rather than toward an error screen.

### 14. Compatibility strategy

TXT books are not a special case. The plain-text parser already produces a full
Document Model through the parser framework, so a TXT book has chapters, sections,
paragraphs and sentences stored exactly like a PDF and flows through
`DocumentPaginationSource` identically. Requirement 7.6 is satisfied because there
is one pipeline, not two.

`StringPaginationSource` is retained as the degradation path — books with no stored
structure and windows whose elements failed to load — and remains the character
access implementation that `DocumentPaginationSource` composes. It is not dead code
under either reading.

Source selection happens once, at construction, behind the `PaginationSource`
abstraction. No downstream component branches on which source is in use.

## Data Models

Backend additions are read-only projections; no table, column, index, or migration
changes. `ElementRecord` and `ElementWindow` are new value objects, and the API
response schema above is their serialization. `document_elements` is queried through
the existing `ix_document_elements_span` and `ix_document_elements_sequence`
indexes; `documents.text` continues to serve canonical text through `/content`.

Flutter additions are the sealed `ReaderElement` hierarchy, `ReaderSpan`,
`ElementWindow`, `DocumentOutline`, `RenderBlock`, and `DocumentPaginationSource`.
No change to `BookContent`, `ReadingProgress`, or `Bookmark`.

## Correctness Properties

Properties that must hold for any document, viewport, typography and settings.
Each is stated so it can be checked mechanically.

### Property 1: Offset equivalence

For identical canonical text, `DocumentPaginationSource` and
`StringPaginationSource` return identical `length`, `scalarSubstring` and
`scalarAt` results, including across surrogate pairs.

**Validates: Requirements 7.5, 7.3**

### Property 2: Pagination invariance

For the same canonical text and `PaginationKey`, page boundaries are identical to
the Sprint 6.1 implementation. Structure never alters a page boundary.

**Validates: Requirements 2.3, 3.11, 8.1**

### Property 3: Anchor round trip

For any saved canonical offset `o`, the restored page satisfies
`page.startOffset ≤ o < page.endOffset`, and re-persisting from that page yields an
offset resolving to the same page.

**Validates: Requirements 3.1, 3.3, 3.4, 3.8, 3.10**

### Property 4: Composition coverage

For any page, the union of composed block visible spans is a subset of the page
span, blocks are pairwise non-overlapping, and every readable element intersecting
the page contributes exactly one block.

**Validates: Requirements 2.1, 2.2, 2.4, 4.11**

### Property 5: Rendered-text containment

Every character rendered on a page appears in that page's canonical slice in the
same relative order. Composition only clips and re-styles; it never rewrites,
reorders, or synthesizes characters.

**Validates: Requirements 2.1, 2.6, 2.7, 4.1**

### Property 6: Selection soundness

Any resolved selection span `[s, e)` satisfies `pageStart ≤ s < e ≤ pageEnd`, and
the submitted text equals the canonical slice of `[s, e)` after the same whitespace
trimming the current implementation applies. An unresolvable selection yields no
submission.

**Validates: Requirements 4.1, 4.2, 4.3, 4.6**

### Property 7: Selection contiguity

A selection spanning adjacent elements resolves to a single contiguous canonical
range; it is never split, truncated, or clipped at an element boundary.

**Validates: Requirements 4.4, 4.5, 4.7, 4.8**

### Property 8: Spacing determinism

The rendered height of a block sequence is a pure function of that sequence, the
typography, and the viewport. Exactly one component contributes inter-block
spacing, so no gap can double.

**Validates: Requirements 2.2, 2.4, 2.18, 5.7**

### Property 9: Render determinism

Two cold launches with the same processed document, viewport, typography and
settings produce identical block sequences and identical page boundaries.

**Validates: Requirements 1.3, 2.1, 6.6**

### Property 10: Boundedness

Resident element records and cached pages are bounded by their LRU capacities and
are independent of total document size.

**Validates: Requirements 6.1, 6.2, 6.7, 6.8**

### Property 11: Context-seam conservatism

For selections intersecting only paragraphs, the widened context query returns
exactly the spans the paragraph-only query returned, so classification results are
unchanged.

**Validates: Requirements 9.1, 9.2, 9.3, 4.10**

### Property 12: Degradation totality

For every element-layer failure mode, the reader still renders the page's canonical
text, and progress, bookmarks and explanations still function.

**Validates: Requirements 1.6, 7.1, 7.7, 7.8**

## Error Handling

Covered in Components and Interfaces §13. Two invariants are worth restating as
acceptance-relevant rules: any element-layer failure degrades to canonical text
rendering rather than an error state, and an unresolvable selection submits nothing
rather than a guessed range.

## Testing Strategy

**Backend unit and integration.** Window query returns overlapping readable
elements plus required structural ancestors; span and element caps enforced with
`truncated` set; ordering deterministic by sequence; ownership and 404 behavior
match `/content`; widened context seam returns spans for code, quote, list item,
footnote, caption and table cell; paragraph-only selections return byte-identical
results to the pre-widening implementation; sentences and table rows excluded from
context; explanation endpoints return success for selections inside every readable
element type.

**Flutter unit.** Element decoding for every type plus unknown-type fallback;
`DocumentOutline` chunk mapping, LRU eviction, and cache-hit behavior;
`DocumentPaginationSource` offsets identical to `StringPaginationSource` for the
same text, including surrogate pairs; `PageComposer` clipping at page boundaries,
sequence ordering, and suppression of empty structural blocks; `BlockSpacing`
producing a single gap between any pair and no doubling at heading-section
adjacency; `SelectionResolver` exact match, duplicate disambiguation by hint,
whitespace-collapsed fallback, cross-element contiguity, and null on failure.

**Flutter widget.** Renderer output per element type — heading prominence,
monospaced code with preserved whitespace, quote treatment, list markers and
ordering, tappable hyperlink with acknowledgement and no navigation, formula
verbatim, footnote and caption de-emphasis; image placeholder showing figure label,
dimensions, page, caption, and performing no byte fetch; table placeholder showing
row count and ordered cell text; unknown element rendering as body text.

**Flutter integration.** Progress restore including the async-late-progress case;
offset preserved across a font-size change; bookmark create, label derivation for a
non-paragraph element, and jump; selection inside paragraph, code block, quote, list
item and across adjacent elements producing correct canonical ranges; degradation to
canonical text when element delivery fails; determinism — identical block sequence
and page boundaries across repeated cold builds with identical inputs.

**Benchmarks.** The three documents and the metric table in §12, recorded in the
sprint report.

## How Sprint 6.6 extends this architecture

No Reader redesign is required, because each planned capability lands on an
existing seam:

- **Rich images.** Register an `ImageRenderer` ahead of the placeholder; add an
  image-asset endpoint keyed by the `sha256:` identifier the parser already emits.
  Composer, paginator, selection and progress are untouched.
- **Real tables.** Register a `TableRenderer` consuming the row and cell elements
  already delivered and already ordered.
- **Inline runs.** Bold, italic, inline code, links and citations become spans
  inside a block's `TextSpan` tree; `RenderBlock` gains inline runs, and canonical
  offsets stay the selection space, so `SelectionResolver` continues to work.
- **Chapter-start pagination.** A structure-aware page-break policy supplied to the
  paginator, deliberately deferred here because it changes page counts.
- **Structure-aware measurement.** Give `PageMeasurer` per-block typography to
  remove the measurement caveat in §6.
- **Navigation, highlights, annotations.** Chapter and section elements already
  carry titles, ids and spans, so a table of contents is a consumer of
  `DocumentOutline`. Highlights and annotations anchor to canonical offsets plus
  element ids, which is why rendering determinism is a goal of this sprint rather
  than a later concern.
- **Hyperlink navigation.** Replace the acknowledgement in the hyperlink renderer;
  nothing else observes it.
