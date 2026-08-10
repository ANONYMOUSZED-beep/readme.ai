import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/domain/document_outline.dart';
import 'package:readme_ai/features/reader/domain/element_window.dart';
import 'package:readme_ai/features/reader/domain/element_window_store.dart';
import 'package:readme_ai/features/reader/domain/reader_element.dart';
import 'package:readme_ai/features/reader/domain/reader_span.dart';
import 'package:readme_ai/features/reader/presentation/pagination/document_page.dart';
import 'package:readme_ai/features/reader/presentation/rendering/page_composer.dart';
import 'package:readme_ai/features/reader/presentation/rendering/render_block.dart';

import '../../helpers/fake_reader_repository.dart';

/// A canonical text containing one of every element shape, laid out so every
/// offset in the fixtures below is computable by hand.
const _chapterTitle = 'Chapter One';
const _sectionTitle = 'Foundations';
const _paragraphOne = 'Reading comes first. Structure serves reading.';
const _code = 'SELECT id\n  FROM users;';
const _quote = 'A book is a mirror.';
const _itemOne = 'First guideline';
const _itemTwo = 'Second guideline';
const _caption = 'Figure 1. A diagram.';
const _footnote = '1. A clarifying note.';
const _cellOne = 'Header';
const _cellTwo = 'Value';
const _paragraphTwo = 'A closing paragraph that ends the page.';

final String _text = [
  _chapterTitle,
  _sectionTitle,
  _paragraphOne,
  _code,
  _quote,
  _itemOne,
  _itemTwo,
  _caption,
  _footnote,
  '$_cellOne | $_cellTwo',
  _paragraphTwo,
].join('\n\n');

(int, int) _at(String fragment) {
  final start = _text.indexOf(fragment);
  return (start, start + fragment.length);
}

ReaderSpan _span(String fragment) {
  final (start, end) = _at(fragment);
  return ReaderSpan(start, end);
}

DocumentPage _page([int? start, int? end]) {
  final from = start ?? 0;
  final to = end ?? _text.length;
  return DocumentPage(
    text: _text.substring(from, to),
    startOffset: from,
    endOffset: to,
  );
}

/// Structure matching [_text], in document order.
List<ReaderElement> _elements() {
  var sequence = 0;
  final chapter = ChapterElement(
    id: 'ch',
    parentId: 'doc',
    orderIndex: 0,
    sequence: sequence++,
    span: ReaderSpan(0, _text.length),
    title: _chapterTitle,
  );
  final section = SectionElement(
    id: 'sec',
    parentId: 'ch',
    orderIndex: 0,
    sequence: sequence++,
    span: ReaderSpan(_at(_sectionTitle).$1, _text.length),
    title: _sectionTitle,
  );
  final paragraph = ParagraphElement(
    id: 'p-1',
    parentId: 'sec',
    orderIndex: 0,
    sequence: sequence++,
    span: _span(_paragraphOne),
  );
  final code = CodeBlockElement(
    id: 'code',
    parentId: 'sec',
    orderIndex: 1,
    sequence: sequence++,
    span: _span(_code),
    language: 'sql',
  );
  final quote = QuoteElement(
    id: 'quote',
    parentId: 'sec',
    orderIndex: 2,
    sequence: sequence++,
    span: _span(_quote),
  );
  final list = ListElement(
    id: 'list',
    parentId: 'sec',
    orderIndex: 3,
    sequence: sequence++,
    span: ReaderSpan(_at(_itemOne).$1, _at(_itemTwo).$2),
  );
  final itemOne = ListItemElement(
    id: 'item-1',
    parentId: 'list',
    orderIndex: 0,
    sequence: sequence++,
    span: _span(_itemOne),
  );
  final itemTwo = ListItemElement(
    id: 'item-2',
    parentId: 'list',
    orderIndex: 1,
    sequence: sequence++,
    span: _span(_itemTwo),
  );
  final image = ImageElement(
    id: 'img',
    parentId: 'sec',
    orderIndex: 4,
    sequence: sequence++,
    identifier: 'sha256:abc',
    captionId: 'cap',
  );
  final caption = CaptionElement(
    id: 'cap',
    parentId: 'img',
    orderIndex: 0,
    sequence: sequence++,
    span: _span(_caption),
    describesId: 'img',
    text: _caption,
  );
  final footnote = FootnoteElement(
    id: 'note',
    parentId: 'sec',
    orderIndex: 5,
    sequence: sequence++,
    span: _span(_footnote),
    label: '1',
  );
  final table = TableElement(
    id: 'tbl',
    parentId: 'sec',
    orderIndex: 6,
    sequence: sequence++,
    span: ReaderSpan(_at(_cellOne).$1, _at(_cellTwo).$2),
  );
  final row = TableRowElement(
    id: 'row',
    parentId: 'tbl',
    orderIndex: 0,
    sequence: sequence++,
    span: ReaderSpan(_at(_cellOne).$1, _at(_cellTwo).$2),
  );
  final cellOne = TableCellElement(
    id: 'cell-1',
    parentId: 'row',
    orderIndex: 0,
    sequence: sequence++,
    span: _span(_cellOne),
    isHeader: true,
    text: _cellOne,
  );
  final cellTwo = TableCellElement(
    id: 'cell-2',
    parentId: 'row',
    orderIndex: 1,
    sequence: sequence++,
    span: _span(_cellTwo),
    text: _cellTwo,
  );
  final hyperlink = HyperlinkElement(
    id: 'link',
    parentId: 'sec',
    orderIndex: 7,
    sequence: sequence++,
    target: 'https://example.test',
    label: 'mirror',
  );
  final paragraphTwo = ParagraphElement(
    id: 'p-2',
    parentId: 'sec',
    orderIndex: 8,
    sequence: sequence++,
    span: _span(_paragraphTwo),
  );

  return [
    chapter,
    section,
    paragraph,
    code,
    quote,
    list,
    itemOne,
    itemTwo,
    image,
    caption,
    footnote,
    table,
    row,
    cellOne,
    cellTwo,
    hyperlink,
    paragraphTwo,
  ];
}

List<RenderBlock> _compose({
  DocumentPage? page,
  List<ReaderElement>? elements,
  PageComposer? composer,
}) => (composer ?? PageComposer()).compose(
  page: page ?? _page(),
  elements: elements ?? _elements(),
);

/// Concatenated text of every block that carries characters.
String _rendered(List<RenderBlock> blocks) =>
    blocks.where((block) => block.carriesText).map((block) => block.text).join();

void main() {
  group('coverage without duplication', () {
    test('blocks cover the page exactly once, in offset order', () {
      final page = _page();
      final blocks = _compose(page: page);

      final textBlocks = blocks.where((block) => block.carriesText).toList();
      var cursor = page.startOffset;
      for (final block in textBlocks) {
        expect(
          block.visibleSpan.start,
          cursor,
          reason: 'gap or overlap before ${block.kind.name}',
        );
        cursor = block.visibleSpan.end;
      }
      expect(cursor, page.endOffset, reason: 'page not fully covered');
    });

    test('rendered text reconstructs the page canonical text exactly', () {
      final page = _page();

      expect(_rendered(_compose(page: page)), page.text);
    });

    test('no character is duplicated across blocks', () {
      final blocks = _compose();

      final seen = <int>{};
      for (final block in blocks.where((b) => b.carriesText)) {
        for (var offset = block.visibleSpan.start;
            offset < block.visibleSpan.end;
            offset++) {
          expect(seen.add(offset), isTrue, reason: 'offset $offset repeated');
        }
      }
    });

    test('every block text is the canonical text of its own span', () {
      final page = _page();

      for (final block in _compose(page: page)) {
        if (!block.carriesText) continue;
        final expected = _text.substring(
          block.visibleSpan.start,
          block.visibleSpan.end,
        );
        expect(block.text, expected, reason: block.kind.name);
      }
    });

    test('rendered text is a subset of the page text', () {
      final page = _page(0, _at(_quote).$2);

      for (final block in _compose(page: page)) {
        if (!block.carriesText) continue;
        expect(page.text.contains(block.text), isTrue);
      }
    });
  });

  group('clipping', () {
    test('an element straddling the page start is clipped to the page', () {
      final (paragraphStart, paragraphEnd) = _at(_paragraphOne);
      final page = _page(paragraphStart + 10, paragraphEnd);

      final blocks = _compose(page: page);
      final block = blocks.firstWhere(
        (block) => block.kind == ReaderElementKind.paragraph,
      );

      expect(block.visibleSpan, ReaderSpan(paragraphStart + 10, paragraphEnd));
      expect(block.clipped, isTrue);
      expect(block.text, _paragraphOne.substring(10));
    });

    test('an element straddling the page end is clipped to the page', () {
      final (paragraphStart, paragraphEnd) = _at(_paragraphOne);
      final page = _page(paragraphStart, paragraphEnd - 12);

      final block = _compose(page: page).single;

      expect(block.visibleSpan.end, paragraphEnd - 12);
      expect(block.clipped, isTrue);
    });

    test('an unclipped element reports clipped false', () {
      final page = _page(0, _at(_paragraphOne).$2);

      final paragraph = _compose(
        page: page,
      ).firstWhere((block) => block.kind == ReaderElementKind.paragraph);

      expect(paragraph.clipped, isFalse);
    });

    test('elements entirely outside the page are dropped', () {
      final page = _page(0, _at(_sectionTitle).$1);

      final blocks = _compose(page: page);

      expect(
        blocks.any((block) => block.kind == ReaderElementKind.codeBlock),
        isFalse,
      );
      expect(_rendered(blocks), page.text);
    });

    test('a clipped page still covers itself completely', () {
      final page = _page(_at(_code).$1 + 4, _at(_itemTwo).$2 - 3);

      expect(_rendered(_compose(page: page)), page.text);
    });
  });

  group('ordering', () {
    test('preserves document order for every element type', () {
      final blocks = _compose();
      final kinds = blocks.map((block) => block.kind).toList();

      int indexOf(ReaderElementKind kind) => kinds.indexOf(kind);

      expect(indexOf(ReaderElementKind.chapter), 0);
      expect(
        indexOf(ReaderElementKind.chapter),
        lessThan(indexOf(ReaderElementKind.section)),
      );
      expect(
        indexOf(ReaderElementKind.section),
        lessThan(indexOf(ReaderElementKind.paragraph)),
      );
      expect(
        indexOf(ReaderElementKind.paragraph),
        lessThan(indexOf(ReaderElementKind.codeBlock)),
      );
      expect(
        indexOf(ReaderElementKind.codeBlock),
        lessThan(indexOf(ReaderElementKind.quote)),
      );
      expect(
        indexOf(ReaderElementKind.quote),
        lessThan(indexOf(ReaderElementKind.listItem)),
      );
      expect(
        indexOf(ReaderElementKind.listItem),
        lessThan(indexOf(ReaderElementKind.image)),
      );
      expect(
        indexOf(ReaderElementKind.image),
        lessThan(indexOf(ReaderElementKind.caption)),
      );
      expect(
        indexOf(ReaderElementKind.caption),
        lessThan(indexOf(ReaderElementKind.footnote)),
      );
      expect(
        indexOf(ReaderElementKind.footnote),
        lessThan(indexOf(ReaderElementKind.table)),
      );
      expect(
        indexOf(ReaderElementKind.table),
        lessThan(indexOf(ReaderElementKind.tableCell)),
      );
    });

    test('input order does not affect output', () {
      final forward = _compose(elements: _elements());
      final reversed = _compose(elements: _elements().reversed.toList());
      final shuffled = _compose(
        elements: _elements()..shuffle(),
      );

      expect(reversed, forward);
      expect(shuffled, forward);
    });

    test('table cells follow their table placeholder in reading order', () {
      final blocks = _compose();
      final kinds = blocks.map((block) => block.kind).toList();

      expect(
        kinds.indexOf(ReaderElementKind.table),
        lessThan(kinds.indexOf(ReaderElementKind.tableCell)),
      );
    });
  });

  group('structural suppression', () {
    test('containers with no text of their own emit no block', () {
      final blocks = _compose();
      final elementIds = blocks
          .map((block) => block.element?.id)
          .whereType<String>()
          .toList();

      // The list and the row are pure containers.
      expect(elementIds.contains('list'), isFalse);
      expect(elementIds.contains('row'), isFalse);
    });

    test('untitled headings produce no heading block', () {
      final page = _page();
      final elements = [
        ChapterElement(
          id: 'ch',
          parentId: 'doc',
          orderIndex: 0,
          sequence: 0,
          span: ReaderSpan(0, _text.length),
        ),
        ParagraphElement(
          id: 'p-1',
          parentId: 'ch',
          orderIndex: 0,
          sequence: 1,
          span: ReaderSpan(0, _text.length),
        ),
      ];

      final blocks = _compose(page: page, elements: elements);

      expect(blocks, hasLength(1));
      expect(blocks.single.kind, ReaderElementKind.paragraph);
    });

    test('a hyperlink is not composed as its own block', () {
      final blocks = _compose();

      // Its label already appears inside the surrounding text; a separate block
      // would print those characters twice.
      expect(
        blocks.any((block) => block.kind == ReaderElementKind.hyperlink),
        isFalse,
      );
      expect(_rendered(blocks), _page().text);
    });

    test('an element fully claimed by an earlier one is suppressed', () {
      final page = _page(0, _at(_paragraphOne).$2);
      final composer = PageComposer();
      final duplicate = ParagraphElement(
        id: 'dup',
        parentId: 'sec',
        orderIndex: 9,
        sequence: 99,
        span: _span(_paragraphOne),
      );

      final blocks = composer.compose(
        page: page,
        elements: [..._elements(), duplicate],
      );

      expect(blocks.map((block) => block.element?.id).contains('dup'), isFalse);
      expect(composer.diagnostics.suppressedBlocks, greaterThan(0));
      expect(_rendered(blocks), page.text);
    });

    test('suppression never loses characters', () {
      final overlapping = ParagraphElement(
        id: 'overlap',
        parentId: 'sec',
        orderIndex: 9,
        sequence: 99,
        span: ReaderSpan(_at(_paragraphOne).$1 + 5, _at(_code).$2),
      );

      final blocks = _compose(elements: [..._elements(), overlapping]);

      expect(_rendered(blocks), _page().text);
    });
  });

  group('headings and gaps', () {
    test('heading text in the flow becomes a heading block', () {
      final blocks = _compose();
      final chapter = blocks.firstWhere(
        (block) => block.kind == ReaderElementKind.chapter,
      );
      final section = blocks.firstWhere(
        (block) => block.kind == ReaderElementKind.section,
      );

      // The block keeps the exact canonical slice, including the separator that
      // follows it; `title` carries the clean text for the renderer.
      expect(chapter.text.trim(), _chapterTitle);
      expect(chapter.title, _chapterTitle);
      expect(chapter.visibleSpan.start, _span(_chapterTitle).start);
      expect(section.text.trim(), _sectionTitle);
      expect(section.title, _sectionTitle);
    });

    test('unclaimed text renders as plain text rather than disappearing', () {
      final page = _page();
      final onlyParagraph = [
        ParagraphElement(
          id: 'p-1',
          parentId: 'sec',
          orderIndex: 0,
          sequence: 5,
          span: _span(_paragraphOne),
        ),
      ];

      final blocks = _compose(page: page, elements: onlyParagraph);

      expect(_rendered(blocks), page.text);
      // Unclaimed runs before and after the paragraph become plain-text blocks,
      // split at blank lines so they still read as separate paragraphs.
      final unknown = blocks
          .where((block) => block.kind == ReaderElementKind.unknown)
          .toList();
      expect(unknown, isNotEmpty);
      expect(
        unknown.any((block) => block.text.contains(_paragraphTwo)),
        isTrue,
      );
    });

    test('no structure at all still renders the whole page', () {
      final page = _page();

      final blocks = _compose(page: page, elements: const []);

      expect(_rendered(blocks), page.text);
      expect(
        blocks.every((block) => block.kind == ReaderElementKind.unknown),
        isTrue,
      );
    });
  });

  group('list markers', () {
    test('unordered lists produce bullets with no number', () {
      final blocks = _compose();
      final items = blocks
          .where((block) => block.kind == ReaderElementKind.listItem)
          .toList();

      expect(items, hasLength(2));
      expect(items.every((item) => item.marker == BlockMarker.bullet), isTrue);
      expect(items.every((item) => item.markerNumber == null), isTrue);
      expect(items.every((item) => item.depth == 1), isTrue);
    });

    test('ordered lists number items from the list start number', () {
      final page = _page(_at(_itemOne).$1, _at(_itemTwo).$2);
      final elements = [
        ListElement(
          id: 'list',
          parentId: 'sec',
          orderIndex: 0,
          sequence: 0,
          span: ReaderSpan(_at(_itemOne).$1, _at(_itemTwo).$2),
          ordered: true,
          startNumber: 3,
        ),
        ListItemElement(
          id: 'item-1',
          parentId: 'list',
          orderIndex: 0,
          sequence: 1,
          span: _span(_itemOne),
        ),
        ListItemElement(
          id: 'item-2',
          parentId: 'list',
          orderIndex: 1,
          sequence: 2,
          span: _span(_itemTwo),
        ),
      ];

      final items = _compose(page: page, elements: elements)
          .where((block) => block.kind == ReaderElementKind.listItem)
          .toList();

      expect(items.map((item) => item.marker), [
        BlockMarker.number,
        BlockMarker.number,
      ]);
      expect(items.map((item) => item.markerNumber), [3, 4]);
    });

    test('ordered lists default to numbering from one', () {
      final page = _page(_at(_itemOne).$1, _at(_itemOne).$2);
      final elements = [
        ListElement(
          id: 'list',
          parentId: 'sec',
          orderIndex: 0,
          sequence: 0,
          span: _span(_itemOne),
          ordered: true,
        ),
        ListItemElement(
          id: 'item-1',
          parentId: 'list',
          orderIndex: 0,
          sequence: 1,
          span: _span(_itemOne),
        ),
      ];

      final item = _compose(page: page, elements: elements).single;

      expect(item.markerNumber, 1);
    });

    test('nested lists increase depth', () {
      final page = _page(_at(_itemOne).$1, _at(_itemTwo).$2);
      final elements = [
        ListElement(
          id: 'outer',
          parentId: 'sec',
          orderIndex: 0,
          sequence: 0,
          span: ReaderSpan(_at(_itemOne).$1, _at(_itemTwo).$2),
        ),
        ListItemElement(
          id: 'outer-item',
          parentId: 'outer',
          orderIndex: 0,
          sequence: 1,
          span: _span(_itemOne),
        ),
        ListElement(
          id: 'inner',
          parentId: 'outer-item',
          orderIndex: 0,
          sequence: 2,
          span: _span(_itemTwo),
        ),
        ListItemElement(
          id: 'inner-item',
          parentId: 'inner',
          orderIndex: 0,
          sequence: 3,
          span: _span(_itemTwo),
        ),
      ];

      final items = _compose(page: page, elements: elements)
          .where((block) => block.kind == ReaderElementKind.listItem)
          .toList();

      expect(items.map((item) => item.depth), [1, 2]);
    });

    test('an orphaned item keeps a bullet', () {
      final page = _page(_at(_itemOne).$1, _at(_itemOne).$2);
      final orphan = ListItemElement(
        id: 'item-1',
        parentId: 'missing-list',
        orderIndex: 0,
        sequence: 0,
        span: _span(_itemOne),
      );

      final block = _compose(page: page, elements: [orphan]).single;

      expect(block.marker, BlockMarker.bullet);
      expect(block.depth, 0);
    });
  });

  group('placeholders', () {
    test('images and tables compose as empty-span placeholders', () {
      final blocks = _compose();
      final image = blocks.firstWhere(
        (block) => block.kind == ReaderElementKind.image,
      );
      final table = blocks.firstWhere(
        (block) => block.kind == ReaderElementKind.table,
      );

      expect(image.isPlaceholder, isTrue);
      expect(image.carriesText, isFalse);
      expect(image.visibleSpan.isEmpty, isTrue);
      expect(image.element, isA<ImageElement>());
      expect(table.isPlaceholder, isTrue);
      expect(table.carriesText, isFalse);
      // A table's cells still carry its text, so nothing is duplicated.
      expect(table.visibleSpan.isEmpty, isTrue);
    });

    test('an image placeholder carries its caption text for labelling', () {
      final image = _compose().firstWhere(
        (block) => block.kind == ReaderElementKind.image,
      );

      expect(image.caption, _caption);
      // The caption still renders as its own block, so it appears exactly once.
      expect(
        _compose().where((block) => block.kind == ReaderElementKind.caption),
        hasLength(1),
      );
    });

    test('captions associate by describesId when captionId is absent', () {
      final elements = _elements()
          .map(
            (element) => element is ImageElement
                ? ImageElement(
                    id: element.id,
                    parentId: element.parentId,
                    orderIndex: element.orderIndex,
                    sequence: element.sequence,
                    identifier: element.identifier,
                  )
                : element,
          )
          .toList();

      final image = _compose(
        elements: elements,
      ).firstWhere((block) => block.kind == ReaderElementKind.image);

      expect(image.caption, _caption);
    });

    test('a placeholder without a caption carries none', () {
      final elements = _elements()
          .where((element) => element.kind != ReaderElementKind.caption)
          .toList();

      final image = _compose(
        elements: elements,
      ).firstWhere((block) => block.kind == ReaderElementKind.image);

      expect(image.caption, isNull);
    });

    test('placeholders never alter coverage', () {
      final withPlaceholders = _compose();
      final withoutPlaceholders = _compose(
        elements: _elements()
            .where(
              (element) =>
                  element.kind != ReaderElementKind.image &&
                  element.kind != ReaderElementKind.table,
            )
            .toList(),
      );

      expect(_rendered(withPlaceholders), _rendered(withoutPlaceholders));
    });
  });

  group('purity and determinism', () {
    test('output is immutable', () {
      final blocks = _compose();

      expect(
        () => blocks.add(
          const RenderBlock(
            kind: ReaderElementKind.paragraph,
            visibleSpan: ReaderSpan(0, 1),
            text: 'x',
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('composition is idempotent', () {
      final first = _compose();
      final second = _compose();
      final third = _compose();

      expect(second, first);
      expect(third, first);
    });

    test('composition never mutates its inputs', () {
      final elements = _elements();
      final snapshot = List.of(elements);
      final page = _page();

      _compose(page: page, elements: elements);

      expect(elements, snapshot);
      expect(page.text, _text);
    });

    test('an empty page composes to nothing', () {
      const page = DocumentPage(text: '', startOffset: 40, endOffset: 40);

      expect(_compose(page: page), isEmpty);
    });
  });

  group('composition from an outline', () {
    test('reads structure through the outline', () async {
      final repository = _StubRepository(_elements());
      final outline = DocumentOutline(
        store: ElementWindowStore(repository: repository, bookId: 'b1'),
      );
      final page = _page();
      await outline.ensureRange(page.startOffset, page.endOffset);

      final blocks = PageComposer().composeFrom(page, outline);

      expect(_rendered(blocks), page.text);
      expect(blocks, _compose(page: page));
    });

    test('an unloaded outline degrades to plain text', () {
      final outline = DocumentOutline(
        store: ElementWindowStore(
          repository: _StubRepository(_elements()),
          bookId: 'b1',
        ),
      );
      final page = _page();

      final blocks = PageComposer().composeFrom(page, outline);

      expect(
        blocks.every((block) => block.kind == ReaderElementKind.unknown),
        isTrue,
      );
      expect(_rendered(blocks), page.text);
    });
  });

  group('diagnostics', () {
    test('count composed, clipped and suppressed blocks and time', () {
      final composer = PageComposer();
      final (paragraphStart, paragraphEnd) = _at(_paragraphOne);

      final full = composer.compose(page: _page(), elements: _elements());
      composer.compose(
        page: _page(paragraphStart + 5, paragraphEnd),
        elements: _elements(),
      );

      final diagnostics = composer.diagnostics;
      expect(diagnostics.compositions, 2);
      expect(diagnostics.composedBlocks, greaterThan(full.length));
      expect(diagnostics.clippedBlocks, greaterThan(0));
      expect(diagnostics.suppressedBlocks, greaterThan(0));
      expect(diagnostics.compositionMicroseconds, greaterThanOrEqualTo(0));
      expect(
        diagnostics.averageCompositionMicroseconds,
        greaterThanOrEqualTo(0),
      );
    });

    test('reset clears counters', () {
      final composer = PageComposer();
      composer.compose(page: _page(), elements: _elements());

      composer.diagnostics.reset();

      expect(composer.diagnostics.compositions, 0);
      expect(composer.diagnostics.composedBlocks, 0);
    });
  });
}

class _StubRepository extends FakeReaderRepository {
  _StubRepository(this.elements);

  final List<ReaderElement> elements;

  @override
  Future<ElementWindow> getElements(
    String bookId, {
    required int start,
    required int end,
  }) async => ElementWindow(
    start: start,
    end: end,
    characterCount: _text.length,
    elements: elements,
  );
}
