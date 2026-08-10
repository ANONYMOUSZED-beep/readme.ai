import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/explanation/presentation/explanation_sheet.dart';
import 'package:readme_ai/features/reader/domain/character_anchor.dart';
import 'package:readme_ai/features/reader/presentation/rendering/page_body.dart';

import '../../helpers/fake_explanation_repository.dart';
import '../../helpers/fake_reader_repository.dart';
import '../../helpers/pump_reader.dart';

/// Selection now spans the whole page, so the gesture targets the page body
/// rather than a single text widget. The toolbar and its Explain action are
/// unchanged from the reader's previous behaviour.
Future<void> _selectAndExplain(WidgetTester tester) async {
  // Press on a glyph near the start of the first rendered line, inside the
  // page's single selection domain.
  final text = find.descendant(
    of: find.byType(PageBody),
    matching: find.byType(Text),
  );
  expect(text, findsWidgets);
  final rect = tester.getRect(text.first);
  await tester.longPressAt(Offset(rect.left + 20, rect.top + 6));
  await tester.pumpAndSettle();
  final contextualExplain = find.descendant(
    of: find.byType(AdaptiveTextSelectionToolbar),
    matching: find.text('Explain'),
  );
  expect(contextualExplain, findsOneWidget);
  await tester.tap(contextualExplain);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('selecting text and tapping Explain opens the sheet', (
    tester,
  ) async {
    final explanation = FakeExplanationRepository();

    await pumpReader(
      tester,
      repository: FakeReaderRepository(),
      explanationRepository: explanation,
    );

    await _selectAndExplain(tester);

    expect(find.byType(ExplanationSheet), findsOneWidget);
    expect(find.text('a small portable computer'), findsOneWidget);
    expect(explanation.calls, 1);
  });

  testWidgets('closing the sheet returns to the reader', (tester) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(),
      explanationRepository: FakeExplanationRepository(),
    );

    await _selectAndExplain(tester);
    expect(find.byType(ExplanationSheet), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Sheet dismissed; the reader (with its selectable page) is still there.
    expect(find.byType(ExplanationSheet), findsNothing);
    expect(find.byType(PageBody), findsOneWidget);
  });

  testWidgets('Explain sends exact Unicode scalar anchors for selected text', (
    tester,
  ) async {
    const text =
        '😀😃😄 A curious reader studies every luminous sentence carefully.';
    final explanation = FakeExplanationRepository();
    await pumpReader(
      tester,
      repository: FakeReaderRepository(
        content: FakeReaderRepository.textContent(text: text),
      ),
      explanationRepository: explanation,
    );

    await _selectAndExplain(tester);

    final start = int.parse(explanation.lastAnchor!);
    final end = int.parse(explanation.lastEndAnchor!);
    expect(
      CharacterAnchor.substring(text, start, end),
      explanation.lastSelectedText,
    );
  });

  testWidgets('current-passage Explain sends exact trimmed scalar range', (
    tester,
  ) async {
    const text = '  😀 Current passage with surrounding whitespace.  \n\nNext.';
    final explanation = FakeExplanationRepository();
    await pumpReader(
      tester,
      repository: FakeReaderRepository(
        content: FakeReaderRepository.textContent(text: text),
      ),
      explanationRepository: explanation,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Explain'));
    await tester.pumpAndSettle();

    final start = int.parse(explanation.lastAnchor!);
    final end = int.parse(explanation.lastEndAnchor!);
    expect(
      CharacterAnchor.substring(text, start, end),
      explanation.lastSelectedText,
    );
  });
}
