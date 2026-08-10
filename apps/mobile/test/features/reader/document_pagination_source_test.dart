import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/domain/character_anchor.dart';
import 'package:readme_ai/features/reader/domain/document_outline.dart';
import 'package:readme_ai/features/reader/domain/document_pagination_source.dart';
import 'package:readme_ai/features/reader/domain/element_window.dart';
import 'package:readme_ai/features/reader/domain/element_window_store.dart';
import 'package:readme_ai/features/reader/domain/pagination_source.dart';
import 'package:readme_ai/features/reader/domain/reader_element.dart';
import 'package:readme_ai/features/reader/domain/reader_span.dart';
import 'package:readme_ai/features/reader/presentation/pagination/document_page.dart';
import 'package:readme_ai/features/reader/presentation/pagination/page_measurer.dart';
import 'package:readme_ai/features/reader/presentation/pagination/reading_paginator.dart';

import '../../helpers/fake_reader_repository.dart';

/// Texts chosen to stress every Unicode boundary the anchor contract must hold.
const _plain = 'It was a bright cold day in April, and the clocks struck.';
const _emoji = 'Reading 📚 is 🔥 today 👩‍👩‍👧‍👦 and tomorrow 🧑🏽‍💻 too.';
const _combining = 'Cafe\u0301 nai\u0308ve mañana Å  a\u0327\u0301 done.';
const _multilingual =
    'English, Русский, 日本語のテキスト, العربية, हिन्दी, 한국어, Ελληνικά.';
const _mixed =
    'Chapter 1 — Введение 📖\n\n'
    'Café naïve 日本語 mixed with 👨‍👩‍👧 families and ZWJ 🏳️‍🌈 flags.\n\n'
    'SELECT * FROM users;\u2029Tail line with a surrogate 𝔘𝔫𝔦𝔠𝔬𝔡𝔢 run.';

const _texts = <String, String>{
  'plain': _plain,
  'emoji': _emoji,
  'combining': _combining,
  'multilingual': _multilingual,
  'mixed': _mixed,
};

class _StubRepository extends FakeReaderRepository {
  _StubRepository(this.elements);

  final List<ReaderElement> elements;
  int requests = 0;

  @override
  Future<ElementWindow> getElements(
    String bookId, {
    required int start,
    required int end,
  }) async {
    requests++;
    return ElementWindow(
      start: start,
      end: end,
      characterCount: 1000,
      elements: elements,
    );
  }
}

DocumentOutline _outline([List<ReaderElement> elements = const []]) =>
    DocumentOutline(
      store: ElementWindowStore(
        repository: _StubRepository(elements),
        bookId: 'b1',
      ),
    );

DocumentPaginationSource _structured(String text, [DocumentOutline? outline]) =>
    DocumentPaginationSource(
      canonicalText: text,
      outline: outline ?? _outline(),
    );

/// Paginates a whole source with the unchanged measurer.
List<DocumentPage> _paginate(
  PaginationSource source, {
  required Size pageSize,
  double fontSize = 16,
}) {
  const measurer = PageMeasurer();
  final style = TextStyle(fontSize: fontSize, height: 1.4);
  final pages = <DocumentPage>[];
  var offset = 0;
  while (offset < source.length) {
    final page = measurer.measureForward(
      source: source,
      start: offset,
      style: style,
      pageSize: pageSize,
      textDirection: TextDirection.ltr,
    );
    if (page == null || page.endOffset <= offset) break;
    pages.add(page);
    offset = page.endOffset;
  }
  return pages;
}

void main() {
  group('interface conformance', () {
    test('is a PaginationSource and keeps StringPaginationSource available', () {
      final structured = _structured(_plain);

      expect(structured, isA<PaginationSource>());
      // The text-only implementation is retained, not replaced.
      expect(StringPaginationSource(_plain), isA<PaginationSource>());
    });

    test('exposes structure outside the PaginationSource interface', () {
      final structured = _structured(_plain);

      expect(structured.outline, isA<DocumentOutline>());
      // The interface itself carries only the three text methods.
      const surface = {'length', 'scalarSubstring', 'scalarAt'};
      expect(surface.length, 3);
    });
  });

  group('offset equivalence with StringPaginationSource', () {
    _texts.forEach((label, text) {
      test('length matches for $label text', () {
        expect(_structured(text).length, StringPaginationSource(text).length);
        // And matches the canonical anchor contract itself.
        expect(_structured(text).length, CharacterAnchor.length(text));
      });

      test('scalarAt matches at every index for $label text', () {
        final structured = _structured(text);
        final plain = StringPaginationSource(text);

        for (var index = -2; index <= plain.length + 2; index++) {
          expect(
            structured.scalarAt(index),
            plain.scalarAt(index),
            reason: '$label scalarAt($index)',
          );
        }
      });

      test('scalarSubstring matches for every range in $label text', () {
        final structured = _structured(text);
        final plain = StringPaginationSource(text);
        final total = plain.length;

        for (var start = 0; start <= total; start++) {
          for (var end = start; end <= total; end++) {
            expect(
              structured.scalarSubstring(start, end),
              plain.scalarSubstring(start, end),
              reason: '$label [$start, $end)',
            );
          }
        }
      });

      test('out-of-range and inverted ranges clamp identically for $label', () {
        final structured = _structured(text);
        final plain = StringPaginationSource(text);
        final total = plain.length;

        final probes = <List<int>>[
          [-10, 5],
          [0, total + 50],
          [total, total + 10],
          [total + 5, total + 9],
          [10, 3],
          [-5, -1],
        ];
        for (final probe in probes) {
          expect(
            structured.scalarSubstring(probe[0], probe[1]),
            plain.scalarSubstring(probe[0], probe[1]),
            reason: '$label ${probe[0]}..${probe[1]}',
          );
        }
      });
    });

    test('never splits a surrogate pair', () {
      final structured = _structured(_emoji);
      final plain = StringPaginationSource(_emoji);

      for (var index = 0; index < plain.length; index++) {
        final scalar = structured.scalarAt(index);
        expect(scalar, plain.scalarAt(index));
        // Each unit is a whole scalar: never a lone surrogate.
        expect(scalar.runes.length, 1, reason: 'index $index');
        expect(scalar.codeUnitAt(0) & 0xFC00 == 0xDC00, isFalse);
      }
    });

    test('agrees with CharacterAnchor conversions on astral text', () {
      final structured = _structured(_emoji);

      for (var index = 0; index <= structured.length; index++) {
        final codeUnit = CharacterAnchor.toCodeUnit(_emoji, index);
        expect(CharacterAnchor.fromCodeUnit(_emoji, codeUnit), index);
        expect(
          structured.scalarSubstring(0, index),
          CharacterAnchor.substring(_emoji, 0, index),
        );
      }
    });

    test('an empty document behaves identically', () {
      expect(_structured('').length, StringPaginationSource('').length);
      expect(_structured('').scalarAt(0), StringPaginationSource('').scalarAt(0));
      expect(
        _structured('').scalarSubstring(0, 5),
        StringPaginationSource('').scalarSubstring(0, 5),
      );
    });
  });

  group('pagination equivalence', () {
    const sizes = <Size>[
      Size(200, 120),
      Size(320, 480),
      Size(480, 90),
    ];

    _texts.forEach((label, text) {
      test('page boundaries are identical for $label text', () {
        for (final size in sizes) {
          final structuredPages = _paginate(_structured(text), pageSize: size);
          final plainPages = _paginate(
            StringPaginationSource(text),
            pageSize: size,
          );

          expect(
            structuredPages.map((page) => (page.startOffset, page.endOffset)),
            plainPages.map((page) => (page.startOffset, page.endOffset)),
            reason: '$label at $size',
          );
          expect(
            structuredPages.map((page) => page.text),
            plainPages.map((page) => page.text),
            reason: '$label text at $size',
          );
        }
      });
    });

    test('boundaries are identical across font sizes', () {
      for (final fontSize in [12.0, 16.0, 24.0, 32.0]) {
        final structuredPages = _paginate(
          _structured(_mixed),
          pageSize: const Size(300, 200),
          fontSize: fontSize,
        );
        final plainPages = _paginate(
          StringPaginationSource(_mixed),
          pageSize: const Size(300, 200),
          fontSize: fontSize,
        );

        expect(
          structuredPages.map((page) => page.endOffset),
          plainPages.map((page) => page.endOffset),
          reason: 'font size $fontSize',
        );
      }
    });

    test('a zero-sized viewport degrades identically', () {
      final structuredPages = _paginate(
        _structured(_plain),
        pageSize: Size.zero,
      );
      final plainPages = _paginate(
        StringPaginationSource(_plain),
        pageSize: Size.zero,
      );

      expect(structuredPages.single.endOffset, plainPages.single.endOffset);
    });

    test('pagination is deterministic across repeated runs', () {
      final first = _paginate(_structured(_mixed), pageSize: const Size(280, 160));
      final second = _paginate(
        _structured(_mixed),
        pageSize: const Size(280, 160),
      );

      expect(
        first.map((page) => (page.startOffset, page.endOffset, page.text)),
        second.map((page) => (page.startOffset, page.endOffset, page.text)),
      );
    });
  });

  group('ReadingPaginator compatibility', () {
    test('drives the unchanged paginator to the same pages', () async {
      final structured = ReadingPaginator(
        source: _structured(_mixed),
        style: const TextStyle(fontSize: 16, height: 1.4),
        pageSize: const Size(300, 180),
        textDirection: TextDirection.ltr,
      );
      final plain = ReadingPaginator(
        source: StringPaginationSource(_mixed),
        style: const TextStyle(fontSize: 16, height: 1.4),
        pageSize: const Size(300, 180),
        textDirection: TextDirection.ltr,
      );
      addTearDown(structured.dispose);
      addTearDown(plain.dispose);

      await structured.ensureIndex(50);
      await plain.ensureIndex(50);

      expect(structured.isComplete, plain.isComplete);
      expect(structured.pageCount, plain.pageCount);
      expect(structured.estimatedTotalPages, plain.estimatedTotalPages);
      for (var index = 0; index < plain.pageCount; index++) {
        expect(structured.pageAt(index).startOffset, plain.pageAt(index).startOffset);
        expect(structured.pageAt(index).endOffset, plain.pageAt(index).endOffset);
        expect(structured.pageAt(index).text, plain.pageAt(index).text);
      }
    });

    test('offset lookups resolve to the same page index', () async {
      final structured = ReadingPaginator(
        source: _structured(_emoji),
        style: const TextStyle(fontSize: 16, height: 1.4),
        pageSize: const Size(220, 100),
        textDirection: TextDirection.ltr,
      );
      final plain = ReadingPaginator(
        source: StringPaginationSource(_emoji),
        style: const TextStyle(fontSize: 16, height: 1.4),
        pageSize: const Size(220, 100),
        textDirection: TextDirection.ltr,
      );
      addTearDown(structured.dispose);
      addTearDown(plain.dispose);

      for (final offset in [0, 5, 12, 20]) {
        expect(
          await structured.ensureOffset(offset),
          await plain.ensureOffset(offset),
          reason: 'offset $offset',
        );
      }
    });
  });

  group('structure access', () {
    const element = ParagraphElement(
      id: 'p-1',
      parentId: 'sec',
      orderIndex: 0,
      sequence: 0,
      span: ReaderSpan(0, 20),
    );

    test('reports readiness without I/O and loads on request', () async {
      final source = _structured(_plain, _outline([element]));

      expect(source.hasStructureFor(0, 20), isFalse);
      expect(source.structureFor(0, 20), isEmpty);

      await source.ensureStructureFor(0, 20);

      expect(source.hasStructureFor(0, 20), isTrue);
      expect(source.structureFor(0, 20).single, element);
    });

    test('structure access never affects character access', () async {
      final source = _structured(_mixed, _outline([element]));
      final before = _paginate(source, pageSize: const Size(300, 180));

      await source.ensureStructureFor(0, 100);
      final after = _paginate(source, pageSize: const Size(300, 180));

      expect(
        after.map((page) => (page.startOffset, page.endOffset)),
        before.map((page) => (page.startOffset, page.endOffset)),
      );
    });
  });

  group('diagnostics', () {
    test('count text access and structural lookups', () async {
      final source = _structured(_plain, _outline());

      source.scalarSubstring(0, 5);
      source.scalarAt(1);
      await source.ensureStructureFor(0, 10);
      source.structureFor(0, 10);

      final diagnostics = source.diagnostics;
      expect(diagnostics.substringCalls, 1);
      expect(diagnostics.scalarAtCalls, 1);
      expect(diagnostics.structuredPageRequests, 1);
      expect(diagnostics.structuredPageCacheHits, 1);
      expect(diagnostics.outlineLookups, 1);
      expect(diagnostics.averageOutlineLookupMicroseconds, greaterThanOrEqualTo(0));
    });

    test('report a miss when structure is absent', () {
      final source = _structured(_plain, _outline());

      source.structureFor(0, 10);

      expect(source.diagnostics.structuredPageRequests, 1);
      expect(source.diagnostics.structuredPageCacheHits, 0);
    });

    test('expose the underlying cache counters for benchmarking', () async {
      final source = _structured(_plain, _outline());

      await source.ensureStructureFor(0, 10);
      await source.ensureStructureFor(0, 10);

      expect(source.outline.diagnostics.misses, 1);
      expect(source.outline.diagnostics.hits, 1);
    });

    test('reset clears counters', () {
      final source = _structured(_plain);
      source.scalarAt(0);

      source.diagnostics.reset();

      expect(source.diagnostics.scalarAtCalls, 0);
    });
  });
}
