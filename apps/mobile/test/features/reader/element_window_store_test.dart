import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/domain/element_window.dart';
import 'package:readme_ai/features/reader/domain/element_window_store.dart';
import 'package:readme_ai/features/reader/domain/reader_element.dart';
import 'package:readme_ai/features/reader/domain/reader_span.dart';

import '../../helpers/fake_reader_repository.dart';

const int _chunk = ElementWindowStore.defaultChunkSize;

/// A repository that serves synthetic chunks and records every request.
class _RecordingRepository extends FakeReaderRepository {
  _RecordingRepository({
    this.characterCount = 200000,
    this.elementsPerChunk = 3,
  });

  final int characterCount;
  final int elementsPerChunk;

  /// Ranges requested, in order.
  final List<(int, int)> requests = [];

  /// Chunk starts that should fail instead of resolving.
  final Set<int> failing = <int>{};

  /// Completers keyed by chunk start, when [manual] is set.
  final Map<int, Completer<ElementWindow>> pending = {};
  bool manual = false;

  @override
  Future<ElementWindow> getElements(
    String bookId, {
    required int start,
    required int end,
  }) {
    requests.add((start, end));
    if (failing.contains(start)) {
      return Future.error(StateError('chunk $start unavailable'));
    }
    if (manual) {
      return (pending[start] ??= Completer<ElementWindow>()).future;
    }
    return Future.value(window(start, end));
  }

  ElementWindow window(int start, int end) => ElementWindow(
    start: start,
    end: end,
    characterCount: characterCount,
    elements: [
      for (var index = 0; index < elementsPerChunk; index++)
        ParagraphElement(
          id: 'p-$start-$index',
          parentId: 'sec',
          orderIndex: index,
          sequence: start + index,
          span: ReaderSpan(start + index * 10, start + index * 10 + 9),
        ),
    ],
  );
}

ElementWindowStore _store(
  _RecordingRepository repository, {
  int capacity = ElementWindowStore.defaultCapacity,
  int chunkSize = _chunk,
}) => ElementWindowStore(
  repository: repository,
  bookId: 'b1',
  capacity: capacity,
  chunkSize: chunkSize,
);

void main() {
  group('chunk indexing', () {
    test('maps offsets to fixed chunks', () {
      final store = _store(_RecordingRepository());

      expect(store.chunkIndexFor(0), 0);
      expect(store.chunkIndexFor(_chunk - 1), 0);
      expect(store.chunkIndexFor(_chunk), 1);
      expect(store.chunkIndexFor(_chunk * 3 + 5), 3);
      // Negative offsets clamp rather than producing a negative chunk.
      expect(store.chunkIndexFor(-50), 0);
    });

    test('a range inside one chunk needs one chunk', () {
      final store = _store(_RecordingRepository());

      expect(store.chunkIndexesFor(10, 500), [0]);
      // The end bound is exclusive, so a range ending at the boundary stays in
      // the first chunk.
      expect(store.chunkIndexesFor(0, _chunk), [0]);
    });

    test('a range straddling a boundary needs exactly two chunks', () {
      final store = _store(_RecordingRepository());

      expect(store.chunkIndexesFor(_chunk - 5, _chunk + 5), [0, 1]);
      expect(store.chunkIndexesFor(_chunk * 2 - 1, _chunk * 2 + 1), [1, 2]);
    });

    test('a degenerate range still resolves to one chunk', () {
      final store = _store(_RecordingRepository());

      expect(store.chunkIndexesFor(500, 500), [0]);
      expect(store.chunkIndexesFor(500, 10), [0]);
    });
  });

  group('cache behaviour', () {
    test('a miss fetches; a hit does not', () async {
      final repository = _RecordingRepository();
      final store = _store(repository);

      await store.ensureRange(0, 100);
      await store.ensureRange(0, 100);
      await store.ensureRange(200, 900);

      expect(repository.requests, [(0, _chunk)]);
      expect(store.isReady(0, 100), isTrue);
      expect(store.residentChunks, 1);
    });

    test('isReady never triggers I/O', () async {
      final repository = _RecordingRepository();
      final store = _store(repository);

      expect(store.isReady(0, 10), isFalse);
      expect(store.cachedElementsIn(0, 10), isEmpty);

      expect(repository.requests, isEmpty);
    });

    test('overlapping requests reuse the chunk they share', () async {
      final repository = _RecordingRepository();
      final store = _store(repository);

      await store.ensureRange(_chunk - 10, _chunk + 10);
      await store.ensureRange(0, 50);
      await store.ensureRange(_chunk + 100, _chunk + 200);

      // Two chunks fetched once each, then served from cache.
      expect(repository.requests, [(0, _chunk), (_chunk, _chunk * 2)]);
    });

    test('character count is learned from the first chunk', () async {
      final repository = _RecordingRepository(characterCount: 2091963);
      final store = _store(repository);

      expect(store.characterCount, isNull);
      await store.ensureRange(0, 10);

      expect(store.characterCount, 2091963);
    });

    test('invalidate drops everything', () async {
      final repository = _RecordingRepository();
      final store = _store(repository);
      await store.ensureRange(0, 10);

      store.invalidate();

      expect(store.residentChunks, 0);
      expect(store.characterCount, isNull);
      await store.ensureRange(0, 10);
      expect(repository.requests, hasLength(2));
    });
  });

  group('LRU eviction', () {
    test('never exceeds capacity', () async {
      final repository = _RecordingRepository();
      final store = _store(repository, capacity: 3);

      for (var index = 0; index < 8; index++) {
        await store.ensureRange(index * _chunk, index * _chunk + 10);
      }

      expect(store.residentChunks, 3);
      expect(store.residentChunkIndexes, [5, 6, 7]);
    });

    test('evicts the least recently used, not the oldest fetched', () async {
      final repository = _RecordingRepository();
      final store = _store(repository, capacity: 2);

      await store.ensureRange(0, 10); // chunk 0
      await store.ensureRange(_chunk, _chunk + 10); // chunk 1
      // Re-read chunk 0, making chunk 1 the least recently used.
      store.cachedElementsIn(0, 10);
      await store.ensureRange(_chunk * 2, _chunk * 2 + 10); // chunk 2

      expect(store.residentChunkIndexes, [0, 2]);
      expect(store.isReady(_chunk, _chunk + 10), isFalse);
    });

    test('memory stays bounded regardless of document size', () async {
      final repository = _RecordingRepository(
        characterCount: 5000000,
        elementsPerChunk: 250,
      );
      final store = _store(repository);

      // Read across a document far larger than the cache.
      for (var index = 0; index < 60; index++) {
        await store.ensureRange(index * _chunk, index * _chunk + 100);
      }

      expect(store.residentChunks, ElementWindowStore.defaultCapacity);
      expect(store.residentElements, ElementWindowStore.defaultCapacity * 250);
      // Bounded by capacity, not by the 60 chunks visited.
      expect(store.residentElements, lessThan(60 * 250));
    });
  });

  group('concurrency', () {
    test('concurrent requests for one chunk share a single fetch', () async {
      final repository = _RecordingRepository()..manual = true;
      final store = _store(repository);

      final first = store.ensureRange(0, 100);
      final second = store.ensureRange(50, 200);
      final third = store.elementsIn(10, 20);

      expect(repository.requests, hasLength(1));
      repository.pending[0]!.complete(repository.window(0, _chunk));
      await Future.wait([first, second, third]);

      expect(repository.requests, hasLength(1));
      expect(store.residentChunks, 1);
    });

    test('concurrent requests for different chunks each fetch once', () async {
      final repository = _RecordingRepository()..manual = true;
      final store = _store(repository);

      final straddling = store.ensureRange(_chunk - 5, _chunk + 5);

      expect(repository.requests, [(0, _chunk), (_chunk, _chunk * 2)]);
      repository.pending[0]!.complete(repository.window(0, _chunk));
      repository.pending[_chunk]!.complete(
        repository.window(_chunk, _chunk * 2),
      );
      await straddling;

      expect(store.residentChunks, 2);
    });

    test('a chunk fetched again after completion is a cache hit', () async {
      final repository = _RecordingRepository();
      final store = _store(repository);

      await Future.wait([
        store.ensureRange(0, 10),
        store.ensureRange(0, 10),
        store.ensureRange(0, 10),
      ]);
      await store.ensureRange(0, 10);

      expect(repository.requests, hasLength(1));
    });
  });

  group('failure handling', () {
    test('a failed fetch propagates and is not cached', () async {
      final repository = _RecordingRepository()..failing.add(0);
      final store = _store(repository);

      await expectLater(store.ensureRange(0, 100), throwsStateError);
      expect(store.residentChunks, 0);
      expect(store.isReady(0, 100), isFalse);

      // The next attempt retries rather than remembering the failure.
      repository.failing.clear();
      await store.ensureRange(0, 100);

      expect(repository.requests, hasLength(2));
      expect(store.isReady(0, 100), isTrue);
    });

    test('a failure does not poison the in-flight table', () async {
      final repository = _RecordingRepository()..failing.add(0);
      final store = _store(repository);

      await expectLater(store.ensureRange(0, 10), throwsStateError);
      await expectLater(store.ensureRange(0, 10), throwsStateError);

      // Each attempt is a fresh request; nothing is left dangling.
      expect(repository.requests, hasLength(2));
    });

    test(
      'one failing chunk does not discard a sibling that succeeded',
      () async {
        final repository = _RecordingRepository()..failing.add(_chunk);
        final store = _store(repository);

        await expectLater(
          store.ensureRange(_chunk - 5, _chunk + 5),
          throwsStateError,
        );

        expect(store.isReady(0, 10), isTrue);
        expect(store.isReady(_chunk, _chunk + 5), isFalse);
      },
    );

    test('prefetch failures are swallowed', () async {
      final repository = _RecordingRepository()..failing.add(_chunk);
      final store = _store(repository);

      await store.prefetchAfter(100);

      expect(store.residentChunks, 0);
    });
  });

  group('prefetch', () {
    test('loads the next chunk once', () async {
      final repository = _RecordingRepository();
      final store = _store(repository);

      await store.ensureRange(0, 100);
      await store.prefetchAfter(100);
      await store.prefetchAfter(200);

      expect(repository.requests, [(0, _chunk), (_chunk, _chunk * 2)]);
      expect(store.isReady(_chunk, _chunk + 10), isTrue);
    });

    test('does not fetch past the end of the document', () async {
      final repository = _RecordingRepository(characterCount: _chunk ~/ 2);
      final store = _store(repository);
      await store.ensureRange(0, 10);

      await store.prefetchAfter(10);

      expect(repository.requests, hasLength(1));
    });
  });

  group('range stitching and determinism', () {
    test(
      'stitches elements across a chunk boundary in document order',
      () async {
        final repository = _RecordingRepository();
        final store = _store(repository);

        final elements = await store.elementsIn(_chunk - 5, _chunk + 5);

        final sequences = elements.map((element) => element.sequence).toList();
        expect(sequences, sorted(sequences));
        expect(elements.map((element) => element.id), [
          'p-0-0',
          'p-0-1',
          'p-0-2',
          'p-$_chunk-0',
          'p-$_chunk-1',
          'p-$_chunk-2',
        ]);
      },
    );

    test('an element delivered in two chunks appears once', () async {
      final repository = _RecordingRepository();
      final store = _store(repository);
      await store.ensureRange(0, _chunk + 10);
      // Simulate the straddling element by asking for both chunks at once.
      final elements = store.cachedElementsIn(0, _chunk + 10);

      final ids = elements.map((element) => element.id).toList();

      expect(ids.toSet().length, ids.length);
    });

    test('repeated retrieval returns identical results', () async {
      final repository = _RecordingRepository();
      final store = _store(repository);

      final first = await store.elementsIn(0, _chunk + 100);
      final second = await store.elementsIn(0, _chunk + 100);
      final third = store.cachedElementsIn(0, _chunk + 100);

      expect(first, second);
      expect(first, third);
      expect(repository.requests, hasLength(2));
    });

    test('dispose stops serving and caching', () async {
      final repository = _RecordingRepository();
      final store = _store(repository);
      await store.ensureRange(0, 10);

      store.dispose();
      await store.ensureRange(_chunk, _chunk + 10);

      expect(store.residentChunks, 0);
      expect(repository.requests, hasLength(1));
    });
  });
}

Matcher sorted(List<int> values) => equals(List.of(values)..sort());
