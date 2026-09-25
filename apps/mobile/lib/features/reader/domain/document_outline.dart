import 'element_window_store.dart';
import 'reader_element.dart';

/// The Reader's structural view of a document.
///
/// Everything above this class — composition, rendering, the whole-passage
/// explain action — asks the outline for structure and never touches transport.
/// The outline consumes only [ElementWindowStore]; it performs no HTTP requests
/// of its own, so caching, chunking, coalescing and bounds live in exactly one
/// place.
///
/// Two guarantees callers depend on:
///
/// * **Deterministic ordering.** Elements always arrive in document order
///   (`sequence`), whatever order chunks were fetched in. This is what allows a
///   composed page to be compared across launches.
/// * **Canonical offsets only.** Every lookup is expressed in canonical scalar
///   offsets, the same anchor space as reading progress, bookmarks and
///   explanations. The outline never invents a coordinate system.
class DocumentOutline {
  DocumentOutline({required ElementWindowStore store}) : _store = store;

  final ElementWindowStore _store;

  /// Total canonical characters in the document, once any window has arrived.
  int? get characterCount => _store.characterCount;

  /// Cache counters for tests and diagnostics only.
  ElementCacheDiagnostics get diagnostics => _store.diagnostics;

  /// Whether every element covering `[start, end)` is already available.
  ///
  /// Never performs I/O, so it is safe to call while building a frame.
  bool isReady(int start, int end) => _store.isReady(start, end);

  /// Loads whatever is missing for `[start, end)`.
  ///
  /// Errors propagate: the caller decides whether to retry or fall back to
  /// canonical text. The outline does not silently swallow a failed window.
  Future<void> ensureRange(int start, int end) =>
      _store.ensureRange(start, end);

  /// Prepares the region after [offset], best-effort, so the next turn is free.
  Future<void> prefetchAfter(int offset) => _store.prefetchAfter(offset);

  /// Elements intersecting `[start, end)`, in document order.
  ///
  /// Returns only what is resident. Combined with [isReady] this lets a build
  /// render immediately when structure is present and degrade when it is not,
  /// without ever awaiting inside `build()`.
  List<ReaderElement> elementsIn(int start, int end) =>
      _store.cachedElementsIn(start, end);

  /// Loads if needed, then returns elements intersecting `[start, end)`.
  Future<List<ReaderElement>> loadElementsIn(int start, int end) =>
      _store.elementsIn(start, end);

  /// Direct children of [parentId] within a loaded range, in sibling order.
  ///
  /// Ordering uses `orderIndex`, the element's position among its siblings,
  /// rather than `sequence`, so a truncated window still lists children in the
  /// order the document defines.
  List<ReaderElement> childrenOf(String parentId, int start, int end) {
    final children = elementsIn(
      start,
      end,
    ).where((element) => element.parentId == parentId).toList();
    children.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return children;
  }

  /// The readable element containing [offset], or `null` when none is resident.
  ///
  /// This is what the whole-passage explain action submits: whatever the reader
  /// is currently positioned inside, be it a paragraph, a code block, a list
  /// item, a quote, a caption or a table cell.
  ///
  /// When spans nest or overlap — a table cell inside a row, an element split
  /// across a chunk boundary — the **innermost** match wins, chosen as the
  /// shortest containing span. Structural elements are excluded, so a chapter
  /// covering the whole book never shadows the paragraph the reader is in.
  ReaderElement? readableElementAt(int offset) {
    if (offset < 0) return null;
    ReaderElement? best;
    int? bestLength;

    // A containing element must start at or before the offset, so a window that
    // begins at the offset is enough to find it.
    for (final element in elementsIn(offset, offset + 1)) {
      if (!element.isReadable) continue;
      final span = element.span;
      if (span == null || !span.contains(offset)) continue;
      if (bestLength == null || span.length < bestLength) {
        best = element;
        bestLength = span.length;
        continue;
      }
      // Deterministic tie-break: equal-length spans resolve by document order,
      // so the same offset always yields the same element.
      if (span.length == bestLength && element.sequence < best!.sequence) {
        best = element;
      }
    }
    return best;
  }

  /// Loads the region around [offset] and then resolves the readable element.
  Future<ReaderElement?> loadReadableElementAt(int offset) async {
    if (offset < 0) return null;
    await ensureRange(offset, offset + 1);
    return readableElementAt(offset);
  }

  /// Drops all cached structure, including the document's character count.
  ///
  /// Called when the active document changes or is reprocessed: a reprocessed
  /// book can have different elements, different spans and a different length,
  /// so nothing cached about the previous one may survive.
  void invalidate() => _store.invalidate();

  /// Releases the outline and its underlying store.
  void dispose() => _store.dispose();
}
