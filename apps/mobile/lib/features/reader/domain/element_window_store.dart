import 'dart:async';

import 'element_window.dart';
import 'reader_element.dart';
import 'reader_repository.dart';

/// Cache counters, exposed for tests and diagnostics only.
///
/// Nothing in production reads these; they exist so cache behaviour can be
/// asserted rather than inferred from request logs.
class ElementCacheDiagnostics {
  int hits = 0;
  int misses = 0;
  int evictions = 0;
  int coalescedRequests = 0;
  int prefetchHits = 0;
  int invalidations = 0;

  void reset() {
    hits = 0;
    misses = 0;
    evictions = 0;
    coalescedRequests = 0;
    prefetchHits = 0;
    invalidations = 0;
  }

  @override
  String toString() =>
      'ElementCacheDiagnostics(hits: $hits, misses: $misses, '
      'evictions: $evictions, coalesced: $coalescedRequests, '
      'prefetchHits: $prefetchHits, invalidations: $invalidations)';
}

/// Fetches and caches document elements in fixed canonical-offset chunks.
///
/// A 900-page book holds tens of thousands of elements. Turning a page must
/// never depend on how many there are, so elements are addressed in fixed chunks
/// and only a handful are ever resident.
///
/// Fixed chunks — rather than arbitrary ranges — buy three properties that
/// matter for a reader that must feel instant:
///
/// * **Stable cache keys.** The same offset always maps to the same chunk, so a
///   page revisited is a cache hit, not a refetch.
/// * **Bounded stitching.** A page can straddle at most one boundary, so any
///   range resolves from at most two chunks.
/// * **Predictable prefetch.** The next chunk is knowable before it is needed.
///
/// This is a **pure data cache**. It holds decoded [ElementWindow] values only —
/// never widgets, renderers, `BuildContext`s, `TextPainter`s, or any layout
/// object. Structure is independent of layout, which is why a font-size change
/// invalidates measured pages but never this cache.
class ElementWindowStore {
  ElementWindowStore({
    required ReaderRepository repository,
    required String bookId,
    this.chunkSize = defaultChunkSize,
    this.capacity = defaultCapacity,
  }) : _repository = repository,
       _bookId = bookId,
       assert(chunkSize > 0, 'chunk size must be positive'),
       assert(capacity > 0, 'capacity must allow at least one chunk');

  /// Canonical scalars per chunk: roughly 8–12 pages of body text, so one chunk
  /// covers the reading window plus its look-ahead.
  static const int defaultChunkSize = 20000;

  /// Resident chunks. Eight keeps element residency near 2,000–3,000 records on
  /// the reference book, independent of its ~51,500 total.
  static const int defaultCapacity = 8;

  final ReaderRepository _repository;
  final String _bookId;
  final int chunkSize;
  final int capacity;

  /// Insertion-ordered, so the first key is the least recently used.
  final Map<int, ElementWindow> _chunks = <int, ElementWindow>{};

  /// In-flight fetches, so concurrent readers of one chunk share a single
  /// request instead of stampeding the API on a fast page turn.
  final Map<int, Future<ElementWindow>> _inFlight = <int, Future<ElementWindow>>{};

  bool _disposed = false;

  /// Total canonical characters in the document, once any chunk has arrived.
  int? _characterCount;
  int? get characterCount => _characterCount;

  final ElementCacheDiagnostics _diagnostics = ElementCacheDiagnostics();

  /// Cache counters for tests and diagnostics only.
  ///
  /// Counting is a handful of integer increments and nothing reads these values
  /// in production, so behaviour and UI are unaffected either way.
  ElementCacheDiagnostics get diagnostics => _diagnostics;

  /// The chunk index that owns [offset].
  int chunkIndexFor(int offset) => offset < 0 ? 0 : offset ~/ chunkSize;

  /// Chunk indexes covering `[start, end)` — at most two for a single page.
  List<int> chunkIndexesFor(int start, int end) {
    final safeStart = start < 0 ? 0 : start;
    final safeEnd = end <= safeStart ? safeStart + 1 : end;
    final first = chunkIndexFor(safeStart);
    final last = chunkIndexFor(safeEnd - 1);
    return [for (var index = first; index <= last; index++) index];
  }

  /// Whether every chunk covering `[start, end)` is already resident.
  bool isReady(int start, int end) =>
      chunkIndexesFor(start, end).every(_chunks.containsKey);

  /// Number of resident chunks, for tests and diagnostics.
  int get residentChunks => _chunks.length;

  /// Resident chunk indexes, least recently used first.
  List<int> get residentChunkIndexes => _chunks.keys.toList();

  /// Total resident element records — the memory bound that must not track
  /// document size.
  int get residentElements =>
      _chunks.values.fold(0, (total, window) => total + window.elements.length);

  /// Elements already resident for `[start, end)`, without fetching.
  ///
  /// Safe to call during a build: it never triggers I/O and never mutates the
  /// cache beyond recording recency.
  List<ReaderElement> cachedElementsIn(int start, int end) {
    final chunks = chunkIndexesFor(start, end);
    final collected = <String, ReaderElement>{};
    for (final index in chunks) {
      final window = _chunks[index];
      if (window == null) continue;
      _touch(index);
      for (final element in window.elements) {
        // Range stitching: an element straddling a boundary arrives in both
        // chunks, so identity de-duplicates it.
        collected[element.id] = element;
      }
    }
    final elements = collected.values.toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    return elements;
  }

  /// Ensures every chunk covering `[start, end)` is resident, then returns the
  /// stitched elements for that range.
  Future<List<ReaderElement>> elementsIn(int start, int end) async {
    await ensureRange(start, end);
    return cachedElementsIn(start, end);
  }

  /// Loads any chunks covering `[start, end)` that are not resident.
  ///
  /// Chunks already cached cost nothing. A failed fetch is not cached, so the
  /// next attempt retries rather than remembering an empty window forever.
  Future<void> ensureRange(int start, int end) async {
    if (_disposed) return;
    final missing = <int>[];
    for (final index in chunkIndexesFor(start, end)) {
      if (_chunks.containsKey(index)) {
        _diagnostics.hits++;
      } else {
        _diagnostics.misses++;
        missing.add(index);
      }
    }
    if (missing.isEmpty) return;
    await Future.wait(missing.map(_loadChunk));
  }

  /// Loads the chunk after the one containing [offset], ignoring failures.
  ///
  /// Prefetch is best-effort by design: it exists to make the next turn instant,
  /// and must never surface an error or block the current page.
  Future<void> prefetchAfter(int offset) async {
    if (_disposed) return;
    final next = chunkIndexFor(offset) + 1;
    final total = _characterCount;
    if (total != null && next * chunkSize >= total) return;
    if (_chunks.containsKey(next)) {
      // Already resident: an earlier prefetch (or read) has paid for this turn.
      _diagnostics.prefetchHits++;
      return;
    }
    try {
      await _loadChunk(next);
    } on Object {
      // Ignored: a missed prefetch costs latency, never correctness.
    }
  }

  Future<ElementWindow> _loadChunk(int index) {
    final existing = _inFlight[index];
    if (existing != null) {
      // A concurrent reader already asked for this chunk; share its fetch.
      _diagnostics.coalescedRequests++;
      return existing;
    }

    final future = _fetch(index);
    _inFlight[index] = future;
    return future;
  }

  Future<ElementWindow> _fetch(int index) async {
    final start = index * chunkSize;
    try {
      final window = await _repository.getElements(
        _bookId,
        start: start,
        end: start + chunkSize,
      );
      if (!_disposed) _store(index, window);
      return window;
    } finally {
      _inFlight.remove(index);
    }
  }

  void _store(int index, ElementWindow window) {
    _chunks[index] = window;
    _touch(index);
    if (window.characterCount > 0) {
      _characterCount = window.characterCount;
    }
    while (_chunks.length > capacity) {
      _chunks.remove(_chunks.keys.first);
      _diagnostics.evictions++;
    }
  }

  /// Marks a chunk as most recently used by reinserting it at the end.
  void _touch(int index) {
    final window = _chunks.remove(index);
    if (window != null) _chunks[index] = window;
  }

  /// Drops every cached chunk. Used when the document itself changes.
  ///
  /// ``characterCount`` is cleared too: a reprocessed book can have a different
  /// length, and a stale total would corrupt every progress percentage derived
  /// from it.
  void invalidate() {
    _chunks.clear();
    _characterCount = null;
    _diagnostics.invalidations++;
  }

  /// Releases the store; in-flight results are discarded rather than cached.
  void dispose() {
    _disposed = true;
    _chunks.clear();
  }
}
