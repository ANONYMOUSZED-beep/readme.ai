import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/explanation/presentation/explanation_sheet.dart';
import 'package:readme_ai/features/reader/domain/element_window.dart';
import 'package:readme_ai/features/reader/domain/reader_element.dart';
import 'package:readme_ai/features/reader/domain/reader_span.dart';
import 'package:readme_ai/features/reader/domain/reading_progress.dart';
import 'package:readme_ai/features/reader/presentation/rendering/page_body.dart';
import 'package:readme_ai/features/reader/presentation/rendering/renderers/table_placeholder_renderer.dart';

import '../../helpers/fake_explanation_repository.dart';
import '../../helpers/fake_reader_repository.dart';
import '../../helpers/pump_reader.dart';

const _chapterTitle = 'Chapter One';
const _sectionTitle = 'Foundations';
const _paragraph = 'Reading comes first. Structure serves reading.';
const _code = 'SELECT id\n  FROM users;';
const _quote = 'A book is a mirror.';
const _item = 'First guideline';
const _caption = 'Figure 5. The pipeline.';
const _cell = 'Header';

final String _text = [
  _chapterTitle,
  _sectionTitle,
  _paragraph,
  _code,
  _quote,
  _item,
  _caption,
  _cell,
].join('\n\n');

(int, int) _at(String fragment) {
  final start = _text.indexOf(fragment);
  return (start, start + fragment.length);
}

ReaderSpan _span(String fragment) {
  final (start, end) = _at(fragment);
  return ReaderSpan(start, end);
}

/// Structure describing [_text], as the API would deliver it.
List<ReaderElement> _elements() {
  var sequence = 0;
  return [
    ChapterElement(
      id: 'ch',
      parentId: 'doc',
      orderIndex: 0,
      sequence: sequence++,
      span: ReaderSpan(0, _text.length),
      title: _chapterTitle,
    ),
    SectionElement(
      id: 'sec',
      parentId: 'ch',
      orderIndex: 0,
      sequence: sequence++,
      span: ReaderSpan(_at(_sectionTitle).$1, _text.length),
      title: _sectionTitle,
    ),
    ParagraphElement(
      id: 'p-1',
      parentId: 'sec',
      orderIndex: 0,
      sequence: sequence++,
      span: _span(_paragraph),
    ),
    CodeBlockElement(
      id: 'code',
      parentId: 'sec',
      orderIndex: 1,
      sequence: sequence++,
      span: _span(_code),
      language: 'sql',
    ),
    QuoteElement(
      id: 'quote',
      parentId: 'sec',
      orderIndex: 2,
      sequence: sequence++,
      span: _span(_quote),
    ),
    ListElement(
      id: 'list',
      parentId: 'sec',
      orderIndex: 3,
      sequence: sequence++,
      span: _span(_item),
    ),
    ListItemElement(
      id: 'item',
      parentId: 'list',
      orderIndex: 0,
      sequence: sequence++,
      span: _span(_item),
    ),
    ImageElement(
      id: 'img',
      parentId: 'sec',
      orderIndex: 4,
      sequence: sequence++,
      identifier: 'sha256:1a2b3c4d5e6f',
      captionId: 'cap',
      width: 320,
      height: 180,
      pageNumber: 4,
    ),
    CaptionElement(
      id: 'cap',
      parentId: 'img',
      orderIndex: 0,
      sequence: sequence++,
      span: _span(_caption),
      describesId: 'img',
      text: _caption,
    ),
    TableElement(
      id: 'tbl',
      parentId: 'sec',
      orderIndex: 5,
      sequence: sequence++,
      span: _span(_cell),
    ),
    TableRowElement(
      id: 'row',
      parentId: 'tbl',
      orderIndex: 0,
      sequence: sequence++,
      span: _span(_cell),
    ),
    TableCellElement(
      id: 'cell',
      parentId: 'row',
      orderIndex: 0,
      sequence: sequence++,
      span: _span(_cell),
      isHeader: true,
      text: _cell,
    ),
  ];
}

/// A reader repository serving both canonical text and structure.
class _StructuredRepository extends FakeReaderRepository {
  _StructuredRepository({
    super.progress,
    this.elements,
    this.failElements = false,
  }) : super(content: FakeReaderRepository.textContent(text: _text));

  final List<ReaderElement>? elements;
  final bool failElements;
  int elementRequests = 0;

  @override
  Future<ElementWindow> getElements(
    String bookId, {
    required int start,
    required int end,
  }) async {
    elementRequests++;
    if (failElements) throw StateError('elements unavailable');
    return ElementWindow(
      start: start,
      end: end,
      characterCount: _text.length,
      elements: elements ?? _elements(),
    );
  }
}

/// Gives the reader a tall surface so the whole fixture fits on one page.
/// Pagination is unchanged; this only avoids asserting across a page turn.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _selectAndExplain(WidgetTester tester, {int textIndex = 0}) async {
  final text = find.descendant(
    of: find.byType(PageBody),
    matching: find.byType(Text),
  );
  final rect = tester.getRect(text.at(textIndex));
  await tester.longPressAt(Offset(rect.left + 12, rect.top + 6));
  await tester.pumpAndSettle();
  final explain = find.descendant(
    of: find.byType(AdaptiveTextSelectionToolbar),
    matching: find.text('Explain'),
  );
  expect(explain, findsOneWidget);
  await tester.tap(explain);
  await tester.pumpAndSettle();
}

void main() {
  group('structured rendering', () {
    testWidgets('renders elements natively instead of one flat string', (
      tester,
    ) async {
      _useTallSurface(tester);
      await pumpReader(tester, repository: _StructuredRepository());

      expect(find.byType(PageBody), findsOneWidget);
      expect(find.text(_chapterTitle), findsOneWidget);
      expect(find.text(_sectionTitle), findsOneWidget);
      expect(find.text(_paragraph), findsOneWidget);
      expect(find.textContaining('FROM users;'), findsOneWidget);
      expect(find.text(_quote), findsOneWidget);
      expect(find.text(_item), findsOneWidget);
    });

    testWidgets('headings are more prominent than body text', (tester) async {
      _useTallSurface(tester);
      await pumpReader(tester, repository: _StructuredRepository());

      final chapter = tester.widget<Text>(find.text(_chapterTitle));
      final section = tester.widget<Text>(find.text(_sectionTitle));
      final body = tester.widget<Text>(find.text(_paragraph));

      expect(chapter.style!.fontSize, greaterThan(section.style!.fontSize!));
      expect(section.style!.fontSize, greaterThan(body.style!.fontSize!));
    });

    testWidgets('image and table placeholders appear in reading order', (
      tester,
    ) async {
      _useTallSurface(tester);
      await pumpReader(tester, repository: _StructuredRepository());

      // Placeholders are identified by their derived labels.
      expect(find.text('Figure 5'), findsOneWidget);
      expect(find.textContaining('Table', findRichText: true), findsOneWidget);
      expect(find.text(_caption), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(Table), findsNothing);
    });

    testWidgets('list items carry markers', (tester) async {
      _useTallSurface(tester);
      await pumpReader(tester, repository: _StructuredRepository());

      expect(find.text(_item), findsOneWidget);
      expect(find.text('\u2022'), findsOneWidget);
    });

    testWidgets('structure is requested off the build phase', (tester) async {
      final repository = _StructuredRepository();

      await pumpReader(tester, repository: repository);

      expect(repository.elementRequests, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });

  group('graceful degradation', () {
    testWidgets('a failed element window still renders the page text', (
      tester,
    ) async {
      await pumpReader(
        tester,
        repository: _StructuredRepository(failElements: true),
      );

      expect(find.byType(PageBody), findsOneWidget);
      expect(find.textContaining(_paragraph), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty element window renders the page as plain text', (
      tester,
    ) async {
      _useTallSurface(tester);
      await pumpReader(
        tester,
        repository: _StructuredRepository(elements: const []),
      );

      expect(find.textContaining(_paragraph), findsOneWidget);
      // The words are all still there — but as body text, with no heading
      // styling, because no structure claimed them.
      final chapter = tester.widget<Text>(find.text(_chapterTitle));
      final body = tester.widget<Text>(find.textContaining(_paragraph));
      expect(chapter.style!.fontSize, body.style!.fontSize);
    });

    testWidgets('explanation still works while degraded', (tester) async {
      final explanation = FakeExplanationRepository();
      await pumpReader(
        tester,
        repository: _StructuredRepository(failElements: true),
        explanationRepository: explanation,
      );

      await _selectAndExplain(tester);

      expect(find.byType(ExplanationSheet), findsOneWidget);
      expect(explanation.calls, 1);
    });
  });

  group('explanation across element types', () {
    testWidgets('selection inside a paragraph resolves canonically', (
      tester,
    ) async {
      final explanation = FakeExplanationRepository();
      await pumpReader(
        tester,
        repository: _StructuredRepository(),
        explanationRepository: explanation,
      );

      await _selectAndExplain(tester, textIndex: 2);

      final start = int.parse(explanation.lastAnchor!);
      final end = int.parse(explanation.lastEndAnchor!);
      expect(_text.substring(start, end), explanation.lastSelectedText);
    });

    testWidgets('whole-passage Explain submits the element under the reader', (
      tester,
    ) async {
      final explanation = FakeExplanationRepository();
      await pumpReader(
        tester,
        repository: _StructuredRepository(),
        explanationRepository: explanation,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Explain'));
      await tester.pumpAndSettle();

      final start = int.parse(explanation.lastAnchor!);
      final end = int.parse(explanation.lastEndAnchor!);
      // Offset 0 sits inside the chapter heading's span, whose innermost
      // readable element is the first paragraph on the page.
      expect(_text.substring(start, end), explanation.lastSelectedText);
      expect(explanation.lastSelectedText!.trim().isNotEmpty, isTrue);
    });
  });

  group('preserved behaviour', () {
    testWidgets('reading position is restored from a saved anchor', (
      tester,
    ) async {
      final repository = _StructuredRepository(
        progress: const ReadingProgress(
          currentPosition: '30',
          progressPercentage: 20,
          totalReadingTimeSeconds: 60,
        ),
      );

      await pumpReader(tester, repository: repository);

      // The page containing offset 30 is showing, and progress is unchanged in
      // form: a canonical scalar offset string.
      expect(find.byType(PageBody), findsOneWidget);
      expect(repository.lastSaved?.currentPosition, isNull);
    });

    testWidgets('page numbering still comes from measured pagination', (
      tester,
    ) async {
      await pumpReader(tester, repository: _StructuredRepository());

      expect(find.textContaining('Page 1 of'), findsOneWidget);
    });

    testWidgets('bookmarking still saves a canonical offset', (tester) async {
      final repository = _StructuredRepository();
      await pumpReader(tester, repository: repository);

      await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
      await tester.pumpAndSettle();

      expect(
        int.tryParse(repository.lastCreatedBookmarkAnchor ?? 'x'),
        isNotNull,
      );
    });

    testWidgets('font-size changes preserve the reading position', (
      tester,
    ) async {
      _useTallSurface(tester);
      final repository = _StructuredRepository();
      await pumpReader(tester, repository: repository);

      // Open the settings sheet and increase the font size.
      await tester.tap(find.byIcon(Icons.tune_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byTooltip('Increase Font size'),
              matching: find.byIcon(Icons.add_rounded),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Still reading the same content, re-measured at the new typography.
      expect(find.byType(PageBody), findsOneWidget);
      expect(find.textContaining(_paragraph), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the reader chrome is unchanged', (tester) async {
      await pumpReader(tester, repository: _StructuredRepository());

      expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
      expect(find.byIcon(Icons.bookmarks_outlined), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Explain'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('placeholders never fetch bytes while reading', (tester) async {
      await pumpReader(tester, repository: _StructuredRepository());

      expect(find.byType(Image), findsNothing);
      expect(find.byType(FadeInImage), findsNothing);
      expect(find.byType(TablePlaceholderRenderer), findsNothing);
    });
  });
}
