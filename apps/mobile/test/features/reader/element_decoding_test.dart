import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/data/element_dtos.dart';
import 'package:readme_ai/features/reader/domain/reader_element.dart';
import 'package:readme_ai/features/reader/domain/reader_span.dart';

Map<String, dynamic> _element({
  required String id,
  required String type,
  int orderIndex = 0,
  int sequence = 0,
  String? parentId = 'sec',
  int? start,
  int? end,
  int? pageNumber,
  Map<String, dynamic> payload = const {},
  String? text,
}) => {
  'id': id,
  'parent_id': parentId,
  'type': type,
  'order_index': orderIndex,
  'sequence': sequence,
  'start_offset': start,
  'end_offset': end,
  'page_number': pageNumber,
  'payload': payload,
  'text': text,
};

Map<String, dynamic> _window(
  List<Map<String, dynamic>> elements, {
  int start = 0,
  int end = 20000,
  int characterCount = 500,
  bool truncated = false,
}) => {
  'book_id': 'b1',
  'start': start,
  'end': end,
  'character_count': characterCount,
  'truncated': truncated,
  'elements': elements,
};

T _single<T extends ReaderElement>(Map<String, dynamic> json) {
  final window = ElementWindowDecoder.decode(_window([json]));
  expect(window.skipped, 0);
  expect(window.elements, hasLength(1));
  return window.elements.single as T;
}

void main() {
  group('window metadata', () {
    test('decodes bounds, character count and truncation', () {
      final window = ElementWindowDecoder.decode(
        _window([
          _element(id: 'p', type: 'paragraph', start: 0, end: 30),
        ], start: 20000, end: 40000, characterCount: 2091963, truncated: true),
      );

      expect(window.start, 20000);
      expect(window.end, 40000);
      expect(window.characterCount, 2091963);
      expect(window.truncated, isTrue);
      expect(window.isComplete, isFalse);
      expect(window.skipped, 0);
    });

    test('an empty element list decodes to an empty window', () {
      final window = ElementWindowDecoder.decode(_window([]));

      expect(window.isEmpty, isTrue);
      expect(window.isComplete, isTrue);
    });

    test('a missing element list does not throw', () {
      final window = ElementWindowDecoder.decode({
        'book_id': 'b1',
        'start': 0,
        'end': 10,
        'character_count': 0,
        'truncated': false,
      });

      expect(window.isEmpty, isTrue);
    });
  });

  group('element decoding', () {
    test('chapter and section carry their titles', () {
      final chapter = _single<ChapterElement>(
        _element(
          id: 'ch',
          type: 'chapter',
          parentId: 'doc',
          payload: const {'title': 'Chapter One'},
          start: 0,
          end: 400,
        ),
      );
      final section = _single<SectionElement>(
        _element(
          id: 'sec',
          type: 'section',
          parentId: 'ch',
          payload: const {'title': 'Foundations'},
        ),
      );
      final untitled = _single<ChapterElement>(
        _element(id: 'ch2', type: 'chapter', parentId: 'doc'),
      );

      expect(chapter.title, 'Chapter One');
      expect(chapter.parentId, 'doc');
      expect(chapter.span, const ReaderSpan(0, 400));
      expect(section.title, 'Foundations');
      expect(untitled.title, isNull);
    });

    test('paragraph decodes without expecting text from the server', () {
      final paragraph = _single<ParagraphElement>(
        _element(id: 'p', type: 'paragraph', start: 10, end: 90, pageNumber: 4),
      );

      expect(paragraph.span, const ReaderSpan(10, 90));
      expect(paragraph.pageNumber, 4);
      expect(paragraph.isReadable, isTrue);
    });

    test('code block keeps only its language; text is derived', () {
      final code = _single<CodeBlockElement>(
        _element(
          id: 'c',
          type: 'code_block',
          payload: const {'language': 'sql', 'code': 'SELECT 1;'},
          start: 100,
          end: 120,
        ),
      );

      expect(code.language, 'sql');
      expect(code.span, const ReaderSpan(100, 120));
    });

    test('quote carries attribution when present', () {
      final quote = _single<QuoteElement>(
        _element(
          id: 'q',
          type: 'quote',
          payload: const {'attribution': 'Orwell'},
          start: 0,
          end: 20,
        ),
      );

      expect(quote.attribution, 'Orwell');
    });

    test('list decodes ordering and start number', () {
      final unordered = _single<ListElement>(
        _element(id: 'l', type: 'list', payload: const {'ordered': false}),
      );
      final ordered = _single<ListElement>(
        _element(
          id: 'l2',
          type: 'list',
          payload: const {'ordered': true, 'start_number': 3},
        ),
      );

      expect(unordered.ordered, isFalse);
      expect(unordered.startNumber, isNull);
      expect(ordered.ordered, isTrue);
      expect(ordered.startNumber, 3);
    });

    test('list item decodes with its span', () {
      final item = _single<ListItemElement>(
        _element(
          id: 'i',
          type: 'list_item',
          parentId: 'l',
          start: 65,
          end: 75,
        ),
      );

      expect(item.parentId, 'l');
      expect(item.span, const ReaderSpan(65, 75));
    });

    test('hyperlink takes its target from payload and label from text', () {
      final link = _single<HyperlinkElement>(
        _element(
          id: 'h',
          type: 'hyperlink',
          payload: const {'target': 'https://example.test'},
          text: 'Reference',
        ),
      );

      expect(link.target, 'https://example.test');
      expect(link.label, 'Reference');
      expect(link.span, isNull);
    });

    test('formula preserves its original representation', () {
      final formula = _single<FormulaElement>(
        _element(
          id: 'f',
          type: 'formula',
          payload: const {
            'original_representation': 'E = mc^2',
            'representation_format': 'pdf_text',
          },
          start: 130,
          end: 138,
        ),
      );

      expect(formula.representation, 'E = mc^2');
      expect(formula.representationFormat, 'pdf_text');
    });

    test('image decodes identifier, dimensions, media type and caption link', () {
      final image = _single<ImageElement>(
        _element(
          id: 'img',
          type: 'image',
          payload: const {
            'image_identifier': 'sha256:abc',
            'width': 200,
            'height': 100.5,
            'media_type': 'image/png',
            'caption_id': 'cap',
          },
          pageNumber: 7,
        ),
      );

      expect(image.identifier, 'sha256:abc');
      expect(image.width, 200.0);
      expect(image.height, 100.5);
      expect(image.mediaType, 'image/png');
      expect(image.captionId, 'cap');
      expect(image.pageNumber, 7);
      expect(image.span, isNull);
    });

    test('caption decodes its target and delivered text', () {
      final caption = _single<CaptionElement>(
        _element(
          id: 'cap',
          type: 'caption',
          parentId: 'img',
          payload: const {'describes_id': 'img'},
          text: 'Figure 1. A diagram.',
          start: 140,
          end: 160,
        ),
      );

      expect(caption.describesId, 'img');
      expect(caption.text, 'Figure 1. A diagram.');
    });

    test('table cell decodes header flag and delivered text', () {
      final header = _single<TableCellElement>(
        _element(
          id: 'c1',
          type: 'table_cell',
          parentId: 'row',
          payload: const {'is_header': true},
          text: 'Header',
          start: 166,
          end: 172,
        ),
      );

      expect(header.isHeader, isTrue);
      expect(header.text, 'Header');
    });

    test('footnote decodes label and reference id', () {
      final footnote = _single<FootnoteElement>(
        _element(
          id: 'n',
          type: 'footnote',
          payload: const {'label': '1', 'reference_id': '1'},
          start: 111,
          end: 132,
        ),
      );

      expect(footnote.label, '1');
      expect(footnote.referenceId, '1');
    });
  });

  group('table row counts', () {
    test('are derived from delivered rows, not from the server', () {
      final window = ElementWindowDecoder.decode(
        _window([
          _element(id: 'tbl', type: 'table', sequence: 0, start: 0, end: 40),
          _element(
            id: 'r1',
            type: 'table_row',
            parentId: 'tbl',
            sequence: 1,
            start: 0,
            end: 20,
          ),
          _element(
            id: 'r2',
            type: 'table_row',
            parentId: 'tbl',
            orderIndex: 1,
            sequence: 2,
            start: 20,
            end: 40,
          ),
        ]),
      );

      final table = window.elements.whereType<TableElement>().single;
      expect(table.rowCount, 2);
    });

    test('report only what the window holds when rows are truncated', () {
      final window = ElementWindowDecoder.decode(
        _window([
          _element(id: 'tbl', type: 'table', sequence: 0),
          _element(id: 'r1', type: 'table_row', parentId: 'tbl', sequence: 1),
        ], truncated: true),
      );

      final table = window.elements.whereType<TableElement>().single;
      expect(table.rowCount, 1);
    });

    test('a table with no delivered rows reports zero', () {
      final table = _single<TableElement>(
        _element(id: 'tbl', type: 'table', start: 0, end: 10),
      );

      expect(table.rowCount, 0);
    });
  });
}
