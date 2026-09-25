# ReadMe.ai Reading Experience Contract

## Product north star

> The book remains the center of the experience. AI exists only to help when the reader asks.

ReadMe.ai is a reading companion, not a chat application wrapped around a document. The primary surface must preserve the rhythm, structure, and agency of reading. Explain is available at the point of need, but it never interrupts, rewrites, summarizes, or advances the book without an explicit reader action.

## Content and anchor invariants

1. Extracted structured content is canonical. Visual pages are a presentation-layer projection of that content.
2. A visual page is a contiguous half-open character range: `[startOffset, endOffset)`.
3. Adjacent page ranges must be contiguous, non-overlapping, and lossless. Joining every page's text must reproduce the canonical source exactly.
4. Global character offsets count **Unicode scalar values** (the same unit as Python `len(str)`), and are the canonical position format for reading progress, bookmarks, and selected passages. Flutter converts to UTF-16 code-unit offsets only at rendering and selection boundaries.
5. Source PDF page numbers are metadata only. They must never define reader progress or visual pagination.
6. Reflow caused by viewport size, orientation, font size, line height, theme, or future format support may change page boundaries, but it must not change canonical anchors.
7. After reflow, the visible page is the page containing the saved global anchor.

These rules keep EPUB, HTML, Markdown, and other future structured formats compatible with the same reader domain model.

## Pagination boundaries

`DocumentPaginator` belongs to the Flutter presentation layer. It measures current typography against the available viewport and returns lossless `DocumentPage` ranges. It must not mutate source content, call repositories, know about PDF internals, or persist state.

`PageTurnView` is also presentation-only. It owns temporary interaction and animation state, while `ReaderScreen` owns the current global anchor and persistence. The page-turn animation must never become the source of truth for reading position.

## Navigation and motion

Readers must be able to move through pages with:

- explicit Previous and Next controls;
- left/right edge swipes;
- Left/Right Arrow and Page Up/Page Down keys;
- Space for forward navigation;
- assistive technology through labelled page semantics and labelled controls.

Page turns may use perspective, shadow, and edge highlights to communicate physical continuity. When the platform requests reduced motion, the page changes immediately without a perspective transition.

Text selection has priority over decorative gestures. The central text surface must not register horizontal page-turn drags; swipe navigation is restricted to page-edge regions. This preserves selection-driven Explain on touch and pointer devices.

## Explain contract

Explain is reader-invoked and context-bound:

- A selected passage uses its page-local selection translated to canonical global offsets.
- The persistent Explain action uses the current visible passage when no selection is active.
- AI output appears in a secondary sheet and returns the reader to the book when dismissed.
- Explain must not replace the reader, auto-open, consume the entire primary layout, or turn navigation into a conversation.

## Progress and bookmarks

- Persist the current page's global `startOffset`, not a visual page number.
- Derive percentage only as secondary display data from the canonical offset and content length.
- Bookmark labels and previews come from canonical content near the saved anchor.
- Final progress persistence during widget teardown must use a controller captured while the widget is mounted; never read provider context after deactivation.

## Responsive and accessibility requirements

- Reader width remains bounded for comfortable line length on wide screens.
- Pagination is measured from the actual content viewport after responsive padding and footer space are accounted for.
- Typography changes trigger deterministic reflow and keep the same anchor visible.
- Page state exposes a live semantic label in the form `Page N of M`.
- Navigation controls have descriptive tooltips/labels and disabled boundary states.
- Keyboard navigation is first-class, not a desktop afterthought.
- Color and elevation are supportive; content and navigation must remain understandable without animation.

## Required regression coverage

Changes to the reader must retain automated tests for:

1. exact, contiguous, lossless pagination, including non-BMP Unicode;
2. stable Unicode-scalar global page anchors;
3. active text-scaler participation in page measurement;
4. forward/back edge swipe and explicit controls;
5. keyboard navigation;
6. reduced-motion fallback that retains navigation;
7. synchronization after external anchor changes or reflow;
8. edge gestures staying outside selectable text;
9. progress persistence and bookmark jumps using nonzero global anchors;
10. exact selection-driven Explain anchors;
11. bookmark creation, fallback previews, deletion, and undo;
12. phone and desktop discoverability; and
13. existing unsupported-format and reader-settings behavior.

## Change checklist

Before shipping a reader change:

- [ ] Canonical content and global anchors remain unchanged.
- [ ] Reflow restores the page containing the previous anchor.
- [ ] Explain remains explicit and selection-driven.
- [ ] Text selection is not intercepted by page gestures.
- [ ] Keyboard, semantics, boundaries, and reduced motion work.
- [ ] Focused reader tests, full Flutter tests, analysis, formatting, and a release build pass.
