import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/domain/reader_element.dart';
import 'package:readme_ai/features/reader/domain/reader_span.dart';

ParagraphElement _paragraph({
  String id = 'p-1',
  int sequence = 3,
  ReaderSpan? span = const ReaderSpan(0, 30),
}) => ParagraphElement(
  id: id,
  parentId: 'sec',
  orderIndex: 0,
  sequence: sequence,
  span: span,
  pageNumber: 4,
);

void main() {
  group('ReaderSpan', () {
    test('reports length, emptiness and containment on a half-open range', () {
      const span = ReaderSpan(10, 20);

      expect(span.length, 10);
      expect(span.isEmpty, isFalse);
      expect(span.isNotEmpty, isTrue);
      expect(span.contains(10), isTrue);
      expect(span.contains(19), isTrue);
      // The end bound is exclusive.
      expect(span.contains(20), isFalse);
      expect(span.contains(9), isFalse);

      const empty = ReaderSpan.empty(7);
      expect(empty.isEmpty, isTrue);
      expect(empty.length, 0);
      expect(empty.contains(7), isFalse);
    });

    test('overlap is half-open, so touching spans do not overlap', () {
      const span = ReaderSpan(10, 20);

      expect(span.overlaps(const ReaderSpan(19, 25)), isTrue);
      expect(span.overlaps(const ReaderSpan(0, 11)), isTrue);
      expect(span.overlaps(const ReaderSpan(20, 30)), isFalse);
      expect(span.overlaps(const ReaderSpan(0, 10)), isFalse);
    });

    test('intersect clips to the overlapping part, or returns null', () {
      const span = ReaderSpan(10, 20);

      expect(
        span.intersect(const ReaderSpan(15, 40)),
        const ReaderSpan(15, 20),
      );
      expect(span.intersect(const ReaderSpan(0, 12)), const ReaderSpan(10, 12));
      expect(span.intersect(const ReaderSpan(0, 40)), span);
      expect(span.intersect(const ReaderSpan(20, 30)), isNull);
      expect(span.intersect(const ReaderSpan(0, 10)), isNull);
    });

    test('is a value type', () {
      expect(const ReaderSpan(3, 9), const ReaderSpan(3, 9));
      expect(const ReaderSpan(3, 9).hashCode, const ReaderSpan(3, 9).hashCode);
      expect(const ReaderSpan(3, 9), isNot(const ReaderSpan(3, 10)));
    });

    test('rejects impossible ranges', () {
      expect(() => ReaderSpan(5, 4), throwsAssertionError);
      expect(() => ReaderSpan(-1, 4), throwsAssertionError);
    });
  });

  group('ReaderElement equality', () {
    test('identical data compares equal', () {
      expect(_paragraph(), _paragraph());
      expect(_paragraph().hashCode, _paragraph().hashCode);
    });

    test('any differing field breaks equality', () {
      expect(_paragraph(), isNot(_paragraph(id: 'p-2')));
      expect(_paragraph(), isNot(_paragraph(sequence: 4)));
      expect(_paragraph(), isNot(_paragraph(span: const ReaderSpan(0, 31))));
    });

    test('subclass-specific fields take part in equality', () {
      const base = CodeBlockElement(
        id: 'c',
        parentId: 'sec',
        orderIndex: 0,
        sequence: 1,
        language: 'python',
      );
      const other = CodeBlockElement(
        id: 'c',
        parentId: 'sec',
        orderIndex: 0,
        sequence: 1,
        language: 'sql',
      );

      expect(base, isNot(other));
      expect(
        base,
        const CodeBlockElement(
          id: 'c',
          parentId: 'sec',
          orderIndex: 0,
          sequence: 1,
          language: 'python',
        ),
      );
    });

    test('different types with the same common fields are not equal', () {
      const paragraph = ParagraphElement(
        id: 'x',
        parentId: 'sec',
        orderIndex: 0,
        sequence: 1,
      );
      const listItem = ListItemElement(
        id: 'x',
        parentId: 'sec',
        orderIndex: 0,
        sequence: 1,
      );

      expect(paragraph == listItem, isFalse);
      expect(listItem == paragraph, isFalse);
    });
  });

  group('ReaderElement vocabulary', () {
    test('covers every supported element and excludes sentences', () {
      expect(ReaderElementKind.values.map((kind) => kind.name).toSet(), {
        'chapter',
        'section',
        'paragraph',
        'codeBlock',
        'quote',
        'list',
        'listItem',
        'hyperlink',
        'formula',
        'image',
        'caption',
        'table',
        'tableRow',
        'tableCell',
        'footnote',
        'unknown',
      });
      // Sentences are backend-only: they are sub-spans of paragraphs.
      expect(
        ReaderElementKind.values.any((kind) => kind.name == 'sentence'),
        isFalse,
      );
    });

    test('each element reports its own kind', () {
      const elements = <ReaderElement>[
        ChapterElement(id: 'a', parentId: null, orderIndex: 0, sequence: 0),
        SectionElement(id: 'b', parentId: 'a', orderIndex: 0, sequence: 1),
        ParagraphElement(id: 'c', parentId: 'b', orderIndex: 0, sequence: 2),
        CodeBlockElement(id: 'd', parentId: 'b', orderIndex: 1, sequence: 3),
        QuoteElement(id: 'e', parentId: 'b', orderIndex: 2, sequence: 4),
        ListElement(id: 'f', parentId: 'b', orderIndex: 3, sequence: 5),
        ListItemElement(id: 'g', parentId: 'f', orderIndex: 0, sequence: 6),
        HyperlinkElement(
          id: 'h',
          parentId: 'b',
          orderIndex: 4,
          sequence: 7,
          target: 'https://example.test',
        ),
        FormulaElement(
          id: 'i',
          parentId: 'b',
          orderIndex: 5,
          sequence: 8,
          representation: 'E = mc^2',
        ),
        ImageElement(
          id: 'j',
          parentId: 'b',
          orderIndex: 6,
          sequence: 9,
          identifier: 'sha256:abc',
        ),
        CaptionElement(
          id: 'k',
          parentId: 'j',
          orderIndex: 0,
          sequence: 10,
          describesId: 'j',
        ),
        TableElement(id: 'l', parentId: 'b', orderIndex: 7, sequence: 11),
        TableRowElement(id: 'm', parentId: 'l', orderIndex: 0, sequence: 12),
        TableCellElement(id: 'n', parentId: 'm', orderIndex: 0, sequence: 13),
        FootnoteElement(id: 'o', parentId: 'b', orderIndex: 8, sequence: 14),
        UnknownElement(
          id: 'p',
          parentId: 'b',
          orderIndex: 9,
          sequence: 15,
          rawType: 'interactive_diagram',
        ),
      ];

      expect(elements.map((element) => element.kind).toSet().length, 16);
      expect(
        elements.map((element) => element.kind).toSet(),
        ReaderElementKind.values.toSet(),
      );
    });

    test('readability marks text-bearing elements only', () {
      const readable = <ReaderElement>[
        ParagraphElement(id: 'a', parentId: null, orderIndex: 0, sequence: 0),
        CodeBlockElement(id: 'b', parentId: null, orderIndex: 0, sequence: 1),
        QuoteElement(id: 'c', parentId: null, orderIndex: 0, sequence: 2),
        ListItemElement(id: 'd', parentId: null, orderIndex: 0, sequence: 3),
        FootnoteElement(id: 'e', parentId: null, orderIndex: 0, sequence: 4),
        FormulaElement(
          id: 'f',
          parentId: null,
          orderIndex: 0,
          sequence: 5,
          representation: 'x^2',
        ),
        CaptionElement(
          id: 'g',
          parentId: null,
          orderIndex: 0,
          sequence: 6,
          describesId: 'z',
        ),
        TableCellElement(id: 'h', parentId: null, orderIndex: 0, sequence: 7),
        UnknownElement(
          id: 'i',
          parentId: null,
          orderIndex: 0,
          sequence: 8,
          rawType: 'future',
        ),
      ];
      const structural = <ReaderElement>[
        ChapterElement(id: 'j', parentId: null, orderIndex: 0, sequence: 9),
        SectionElement(id: 'k', parentId: null, orderIndex: 0, sequence: 10),
        ListElement(id: 'l', parentId: null, orderIndex: 0, sequence: 11),
        TableElement(id: 'm', parentId: null, orderIndex: 0, sequence: 12),
        TableRowElement(id: 'n', parentId: null, orderIndex: 0, sequence: 13),
        ImageElement(
          id: 'o',
          parentId: null,
          orderIndex: 0,
          sequence: 14,
          identifier: 'sha256:abc',
        ),
        HyperlinkElement(
          id: 'p',
          parentId: null,
          orderIndex: 0,
          sequence: 15,
          target: 'https://example.test',
        ),
      ];

      expect(readable.every((element) => element.isReadable), isTrue);
      expect(structural.any((element) => element.isReadable), isFalse);
    });

    test(
      'elements carry source page metadata without it affecting hierarchy',
      () {
        const element = ParagraphElement(
          id: 'a',
          parentId: 'sec',
          orderIndex: 2,
          sequence: 9,
          span: ReaderSpan(100, 200),
          pageNumber: 42,
        );

        expect(element.pageNumber, 42);
        // Hierarchy comes from parentId/orderIndex/sequence only.
        expect(element.parentId, 'sec');
        expect(element.orderIndex, 2);
        expect(element.sequence, 9);
      },
    );

    test('span-less elements expose a null span', () {
      const image = ImageElement(
        id: 'a',
        parentId: 'sec',
        orderIndex: 0,
        sequence: 1,
        identifier: 'sha256:abc',
      );

      expect(image.span, isNull);
      expect(image.isReadable, isFalse);
    });
  });
}
