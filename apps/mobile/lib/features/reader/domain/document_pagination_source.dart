import 'document_outline.dart';
import 'pagination_source.dart';
import 'reader_element.dart';

/// Lightweight counters for Wave 8 benchmarking. Nothing branches on them.
class PaginationSourceDiagnostics {
  int substringCalls = 0;
  int scalarAtCalls = 0;
  int outlineLookups = 0;
  int structuredPageRequests = 0;
  int structuredPageCacheHits = 0;

  /// Total microseconds spent resolving structure for a page.
  int outlineLookupMicroseconds = 0;

  /// Mean microseconds per structural lookup, or 0 when none were made.
  double get averageOutlineLookupMicroseconds =>
      outlineLookups == 0 ? 0 : outlineLookupMicroseconds / outlineLookups;

  void reset() {
    substringCalls = 0;
    scalarAtCalls = 0;
    outlineLookups = 0;
    structuredPageRequests = 0;
    structuredPageCacheHits = 0;
    outlineLookupMicroseconds = 0;
  }

  @override
  String toString() =>
      'PaginationSourceDiagnostics(substrings: $substringCalls, '
      'scalarAt: $scalarAtCalls, outlineLookups: $outlineLookups, '
      'pageRequests: $structuredPageRequests, '
      'pageCacheHits: $structuredPageCacheHits, '
      'avgLookupUs: ${averageOutlineLookupMicroseconds.toStringAsFixed(1)})';
}

/// A [PaginationSource] that carries document structure alongside its text.
///
/// The critical property is what this class *does not* do. Character access is
/// delegated verbatim to a composed [StringPaginationSource], so canonical
/// offsets are identical to the text-only source **by construction** rather than
/// by agreement between two implementations. Measurement therefore sees exactly
/// the same characters at exactly the same offsets, and page boundaries produced
/// by `PageMeasurer` are unchanged from Sprint 6.1 — which is why reading
/// progress and bookmarks need no migration.
///
/// Structure is exposed through [outline], deliberately *outside* the
/// [PaginationSource] interface. The paginator keeps depending on three methods
/// and knows nothing about elements; only the composer reaches for structure.
/// Adding structure did not widen the pagination contract.
///
/// Canonical scalar offsets remain the only coordinate system here. This class
/// introduces none.
class DocumentPaginationSource implements PaginationSource {
  DocumentPaginationSource({
    required String canonicalText,
    required DocumentOutline outline,
  }) : _text = StringPaginationSource(canonicalText),
       _outline = outline;

  final StringPaginationSource _text;
  final DocumentOutline _outline;
  final PaginationSourceDiagnostics _diagnostics = PaginationSourceDiagnostics();

  /// Structural access for the composer. Not part of [PaginationSource].
  DocumentOutline get outline => _outline;

  /// Measurements for benchmarking. Test and diagnostic use only.
  PaginationSourceDiagnostics get diagnostics => _diagnostics;

  // --- PaginationSource: delegated without reinterpretation ------------------

  @override
  int get length => _text.length;

  @override
  String scalarSubstring(int start, int end) {
    _diagnostics.substringCalls++;
    return _text.scalarSubstring(start, end);
  }

  @override
  String scalarAt(int index) {
    _diagnostics.scalarAtCalls++;
    return _text.scalarAt(index);
  }

  // --- Structure for a measured page ---------------------------------------

  /// Whether structure for `[start, end)` is resident, without any I/O.
  bool hasStructureFor(int start, int end) => _outline.isReady(start, end);

  /// Loads structure for `[start, end)`, for callers preparing a page.
  ///
  /// Errors propagate so the caller can degrade to canonical text rather than
  /// having a failure hidden here.
  Future<void> ensureStructureFor(int start, int end) =>
      _outline.ensureRange(start, end);

  /// Structure covering `[start, end)`, in document order, from cache only.
  ///
  /// Timed so Wave 8 can attribute page-preparation cost between structural
  /// lookup and text measurement.
  List<ReaderElement> structureFor(int start, int end) {
    _diagnostics.structuredPageRequests++;
    if (_outline.isReady(start, end)) {
      _diagnostics.structuredPageCacheHits++;
    }
    final watch = Stopwatch()..start();
    final elements = _outline.elementsIn(start, end);
    watch.stop();
    _diagnostics.outlineLookups++;
    _diagnostics.outlineLookupMicroseconds += watch.elapsedMicroseconds;
    return elements;
  }
}
