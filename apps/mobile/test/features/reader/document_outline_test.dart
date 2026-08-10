import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/domain/document_outline.dart';
import 'package:readme_ai/features/reader/domain/element_window.dart';
import 'package:readme_ai/features/reader/domain/element_window_store.dart';
import 'package:readme_ai/features/reader/domain/reader_element.dart';
import 'package:readme_ai/features/reader/domain/reader_span.dart';

import '../../helpers/fake_reader_repository.dart';

const int _chunk = ElementWindowStore.defaultChunkSize;

/// Serves synthetic chunks built from a per-document element factory.
class _OutlineRepository extends FakeReaderRepository {
  _OutlineRepository({required this.build});

  /// Builds the elements for a chunk starting at the given offset.
  List<ReaderElement> Function(int chunkStart) build;
  int characterCount = 200000;

  final List<(int, int)> requests = [];
  final Set<int> failing = <int>{};

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
    return Future.value(
      ElementWindow(
        start: start,
        end: end,
        characterCount: characterCount,
        elements: build(start),
      ),
    );
  }
}

ParagraphElement _paragraph(
  String id,
  int start,
  int end, {
  int sequence = 0,
  String parent = 'sec',
  int order = 0,
}) => ParagraphElement(
  id: id,
  parentId: parent,
  orderIndex: order,
  sequence: sequence,
  span: ReaderSpan(start, end),
);

/// A chapter/section wrapper plus a paragraph, a code block, a list with items,
/// a table with a cell, and a caption — one of each shape the outline must
/// resolve.
List<ReaderElement> _richChunk(int offset) => [
  const ChapterElement(
    id: 'ch',
    parentId: 'doc',
    orderIndex: 0,
    sequence: 0,
    span: ReaderSpan(0, 900),
  ),
  const SectionElement(
    id: 'sec',
    parentId: 'ch',
    orderIndex: 0,
    sequence: 1,
    span: ReaderSpan(0, 900),
  ),
  _paragraph('p-1', 0, 100, sequence: 2),
  const CodeBlockElement(
    id: 'code',
    parentId: 'sec',
    orderIndex: 1,
    sequence: 3,
    span: ReaderSpan(110, 200),
    language: 'sql',
  ),
  const ListElement(
    id: 'list',
    parentId: 'sec',
    orderIndex: 2,
    sequence: 4,
    span: ReaderSpan(210, 300),
  ),
  const ListItemElement(
    id: 'item-1',
    parentId: 'list',
    orderIndex: 0,
    sequence: 5,
    span: ReaderSpan(210, 250),
  ),
  const ListItemElement(
    id: 'item-2',
    parentId: 'list',
    orderIndex: 1,
    sequence: 6,
    span: ReaderSpan(255, 300),
  ),
  const TableElement(
    id: 'tbl',
    parentId: 'sec',
    orderIndex: 3,
    sequence: 7,
    span: ReaderSpan(310, 400),
  ),
  const TableRowElement(
    id: 'row',
    parentId: 'tbl',
    orderIndex: 0,
    sequence: 8,
    span: ReaderSpan(310, 400),
  ),
  const TableCellElement(
    id: 'cell',
    parentId: 'row',
    orderIndex: 0,
    sequence: 9,
    span: ReaderSpan(310, 350),
    text: 'Header',
  ),
  const ImageElement(
    id: 'img',
    parentId: 'sec',
    orderIndex: 4,
    sequence: 10,
    identifier: 'sha256:abc',
    captionId: 'cap',
  ),
  const CaptionElement(
    id: 'cap',
    parentId: 'img',
    orderIndex: 0,
    sequence: 11,
    span: ReaderSpan(410, 450),
    describesId: 'img',
    text: 'Figure 1.',
  ),
];

DocumentOutline _outline(
  _OutlineRepository repository, {
  int capacity = ElementWindowStore.defaultCapacity,
}) => DocumentOutline(
  store: ElementWindowStore(
    repository: repository,
    bookId: 'b1',
    capacity: capacity,
  ),
);

void main() {
  group('construction and readiness', () {
    test('starts empty and performs no I/O until asked', () {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);

      expect(outline.isReady(0, 100), isFalse);
      expect(outline.elementsIn(0, 100), isEmpty);
      expect(outline.readableElementAt(50), isNull);
      expect(outline.characterCount, isNull);
      expect(repository.requests, isEmpty);
    });

    test('ensureRange loads and then reports ready', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);

      await outline.ensureRange(0, 100);

      expect(outline.isReady(0, 100), isTrue);
      expect(outline.characterCount, 200000);
      expect(repository.requests, [(0, _chunk)]);
    });

    test('errors from the store propagate for the caller to handle', () async {
      final repository = _OutlineRepository(build: _richChunk)..failing.add(0);
      final outline = _outline(repository);

      await expectLater(outline.ensureRange(0, 100), throwsStateError);
      expect(outline.isReady(0, 100), isFalse);
    });
  });

  group('deterministic ordering', () {
    test('elements arrive in document order', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);

      final elements = await outline.loadElementsIn(0, 500);

      final sequences = elements.map((element) => element.sequence).toList();
      expect(sequences, equals(List.of(sequences)..sort()));
      expect(elements.first.id, 'ch');
    });

    test('repeated lookups return identical results', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);
      await outline.ensureRange(0, 500);

      expect(outline.elementsIn(0, 500), outline.elementsIn(0, 500));
      expect(outline.readableElementAt(50), outline.readableElementAt(50));
    });
  });

  group('chunk boundary traversal', () {
    test('stitches elements across a boundary in document order', () async {
      final repository = _OutlineRepository(
        build: (offset) => [
          _paragraph('p-$offset-a', offset, offset + 50, sequence: offset),
          _paragraph(
            'p-$offset-b',
            offset + 60,
            offset + 110,
            sequence: offset + 1,
            order: 1,
          ),
        ],
      );
      final outline = _outline(repository);

      final elements = await outline.loadElementsIn(_chunk - 10, _chunk + 100);

      expect(elements.map((element) => element.id), [
        'p-0-a',
        'p-0-b',
        'p-$_chunk-a',
        'p-$_chunk-b',
      ]);
      expect(repository.requests, hasLength(2));
    });

    test('an element straddling a boundary resolves once, from either side', () async {
      // The same element is delivered in both chunks, as the API does.
      final straddling = _paragraph(
        'straddle',
        _chunk - 20,
        _chunk + 20,
        sequence: 100,
      );
      final repository = _OutlineRepository(
        build: (offset) => [straddling],
      );
      final outline = _outline(repository);

      await outline.ensureRange(_chunk - 20, _chunk + 20);
      final elements = outline.elementsIn(_chunk - 20, _chunk + 20);

      expect(elements, hasLength(1));
      expect(outline.readableElementAt(_chunk - 1)?.id, 'straddle');
      expect(outline.readableElementAt(_chunk + 1)?.id, 'straddle');
    });

    test('readableElementAt works in a later chunk', () async {
      final repository = _OutlineRepository(
        build: (offset) => [
          _paragraph('p-$offset', offset + 5, offset + 95, sequence: offset),
        ],
      );
      final outline = _outline(repository);

      final element = await outline.loadReadableElementAt(_chunk * 3 + 50);

      expect(element?.id, 'p-${_chunk * 3}');
    });
  });

  group('readableElementAt', () {
    test('finds the readable element containing an offset', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);
      await outline.ensureRange(0, 500);

      expect(outline.readableElementAt(0)?.id, 'p-1');
      expect(outline.readableElementAt(99)?.id, 'p-1');
      expect(outline.readableElementAt(150)?.id, 'code');
      expect(outline.readableElementAt(220)?.id, 'item-1');
      expect(outline.readableElementAt(260)?.id, 'item-2');
      expect(outline.readableElementAt(420)?.id, 'cap');
    });

    test('prefers the innermost span when elements nest', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);
      await outline.ensureRange(0, 500);

      // The cell, its row and the table all cover offset 320; the cell wins.
      expect(outline.readableElementAt(320)?.id, 'cell');
      // Chapter and section span the whole document but are structural.
      expect(outline.readableElementAt(50)?.id, 'p-1');
    });

    test('never returns a structural element', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);
      await outline.ensureRange(0, 500);

      for (var offset = 0; offset < 500; offset += 7) {
        final element = outline.readableElementAt(offset);
        if (element == null) continue;
        expect(element.isReadable, isTrue, reason: 'offset $offset');
        expect(element.kind, isNot(ReaderElementKind.chapter));
        expect(element.kind, isNot(ReaderElementKind.section));
        expect(element.kind, isNot(ReaderElementKind.list));
        expect(element.kind, isNot(ReaderElementKind.table));
        expect(element.kind, isNot(ReaderElementKind.tableRow));
      }
    });

    test('returns null in a gap between elements and for negatives', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);
      await outline.ensureRange(0, 500);

      // 105 falls between the paragraph (ends 100) and the code block (starts 110).
      expect(outline.readableElementAt(105), isNull);
      expect(outline.readableElementAt(-1), isNull);
      expect(outline.readableElementAt(880), isNull);
    });

    test('supports the whole-passage explain action for every readable kind', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);
      await outline.ensureRange(0, 500);

      final kinds = {
        for (final offset in [50, 150, 220, 320, 420])
          outline.readableElementAt(offset)!.kind,
      };

      expect(kinds, {
        ReaderElementKind.paragraph,
        ReaderElementKind.codeBlock,
        ReaderElementKind.listItem,
        ReaderElementKind.tableCell,
        ReaderElementKind.caption,
      });
    });
  });

  group('parent hierarchy', () {
    test('exposes stable parent relationships', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);
      await outline.ensureRange(0, 500);
      final byId = {for (final e in outline.elementsIn(0, 500)) e.id: e};

      expect(byId['sec']!.parentId, 'ch');
      expect(byId['p-1']!.parentId, 'sec');
      expect(byId['item-1']!.parentId, 'list');
      expect(byId['cell']!.parentId, 'row');
      expect(byId['cap']!.parentId, 'img');
    });

    test('childrenOf lists direct children in sibling order', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);
      await outline.ensureRange(0, 500);

      final sectionChildren = outline.childrenOf('sec', 0, 500);
      final listItems = outline.childrenOf('list', 0, 500);

      expect(sectionChildren.map((element) => element.id), [
        'p-1',
        'code',
        'list',
        'tbl',
        'img',
      ]);
      expect(listItems.map((element) => element.id), ['item-1', 'item-2']);
      expect(outline.childrenOf('p-1', 0, 500), isEmpty);
    });
  });

  group('invalidation and document switching', () {
    test('invalidate clears structure and the character count', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);
      await outline.ensureRange(0, 500);

      outline.invalidate();

      expect(outline.isReady(0, 500), isFalse);
      expect(outline.elementsIn(0, 500), isEmpty);
      expect(outline.characterCount, isNull);
      expect(outline.diagnostics.invalidations, 1);
    });

    test('a reprocessed document is refetched, not served stale', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);
      await outline.ensureRange(0, 500);
      expect(outline.readableElementAt(50)?.id, 'p-1');

      // The book is reprocessed: different elements, different length.
      repository
        ..build = ((offset) => [_paragraph('rebuilt', 0, 80, sequence: 0)])
        ..characterCount = 999;
      outline.invalidate();
      await outline.ensureRange(0, 500);

      expect(outline.readableElementAt(50)?.id, 'rebuilt');
      expect(outline.characterCount, 999);
      expect(repository.requests, hasLength(2));
    });

    test('dispose stops serving', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);
      await outline.ensureRange(0, 500);

      outline.dispose();

      expect(outline.elementsIn(0, 500), isEmpty);
    });
  });

  group('diagnostics', () {
    test('count hits and misses per chunk consulted', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);

      await outline.ensureRange(0, 100); // miss
      await outline.ensureRange(0, 100); // hit
      await outline.ensureRange(_chunk - 5, _chunk + 5); // hit + miss

      expect(outline.diagnostics.misses, 2);
      expect(outline.diagnostics.hits, 2);
    });

    test('count evictions', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository, capacity: 2);

      for (var index = 0; index < 5; index++) {
        await outline.ensureRange(index * _chunk, index * _chunk + 10);
      }

      expect(outline.diagnostics.evictions, 3);
    });

    test('count coalesced requests', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);

      await Future.wait([
        outline.ensureRange(0, 10),
        outline.ensureRange(20, 30),
        outline.ensureRange(40, 50),
      ]);

      // One real fetch; the other two joined it.
      expect(repository.requests, hasLength(1));
      expect(outline.diagnostics.coalescedRequests, 2);
    });

    test('count prefetch hits when the next chunk is already resident', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);

      await outline.ensureRange(0, 10);
      await outline.prefetchAfter(10); // fetches chunk 1
      await outline.prefetchAfter(10); // already resident

      expect(outline.diagnostics.prefetchHits, 1);
      expect(repository.requests, hasLength(2));
    });

    test('reset clears counters without touching the cache', () async {
      final repository = _OutlineRepository(build: _richChunk);
      final outline = _outline(repository);
      await outline.ensureRange(0, 10);

      outline.diagnostics.reset();

      expect(outline.diagnostics.misses, 0);
      expect(outline.diagnostics.hits, 0);
      expect(outline.isReady(0, 10), isTrue);
    });
  });
}
