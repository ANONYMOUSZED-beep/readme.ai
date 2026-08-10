import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/domain/reader_element.dart';
import 'package:readme_ai/features/reader/domain/reader_span.dart';
import 'package:readme_ai/features/reader/presentation/rendering/block_spacing.dart';
import 'package:readme_ai/features/reader/presentation/rendering/element_renderer.dart';
import 'package:readme_ai/features/reader/presentation/rendering/element_renderer_registry.dart';
import 'package:readme_ai/features/reader/presentation/rendering/page_body.dart';
import 'package:readme_ai/features/reader/presentation/rendering/render_block.dart';
import 'package:readme_ai/features/reader/presentation/rendering/renderers/body_text_renderer.dart';
import 'package:readme_ai/features/reader/presentation/rendering/renderers/code_block_renderer.dart';
import 'package:readme_ai/features/reader/presentation/rendering/renderers/heading_renderer.dart';
import 'package:readme_ai/features/reader/presentation/rendering/renderers/hyperlink_renderer.dart';
import 'package:readme_ai/features/reader/presentation/rendering/renderers/image_placeholder_renderer.dart';
import 'package:readme_ai/features/reader/presentation/rendering/renderers/list_item_renderer.dart';
import 'package:readme_ai/features/reader/presentation/rendering/renderers/paragraph_renderer.dart';
import 'package:readme_ai/features/reader/presentation/rendering/renderers/table_placeholder_renderer.dart';

const _palette = RenderPalette(
  text: Color(0xFF101010),
  muted: Color(0xFF666666),
  accent: Color(0xFF3355FF),
  surface: Color(0xFFF3F3F3),
  outline: Color(0xFFDDDDDD),
);

RenderContext _render({void Function(String)? onLinkTap}) => RenderContext(
  bodyStyle: const TextStyle(fontSize: 16, height: 1.4),
  colors: _palette,
  onLinkTap: onLinkTap,
);

RenderBlock _block(
  ReaderElementKind kind, {
  String text = 'Reading comes first.',
  ReaderElement? element,
  String? title,
  BlockMarker marker = BlockMarker.none,
  int? markerNumber,
  int depth = 0,
}) => RenderBlock(
  kind: kind,
  visibleSpan: const ReaderSpan(0, 20),
  text: text,
  element: element,
  title: title,
  marker: marker,
  markerNumber: markerNumber,
  depth: depth,
);

Future<void> _pump(
  WidgetTester tester,
  List<RenderBlock> blocks, {
  ElementRendererRegistry? registry,
  void Function(String)? onLinkTap,
  BlockSpacing spacing = const BlockSpacing(),
  double width = 360,
  double height = 640,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: height,
          child: PageBody(
            blocks: blocks,
            registry: registry ?? ElementRendererRegistry.standard(),
            renderContext: _render(onLinkTap: onLinkTap),
            explainLabel: 'Explain',
            spacing: spacing,
          ),
        ),
      ),
    ),
  );
}

/// The heights of the spacer boxes PageBody inserted.
List<double> _gaps(WidgetTester tester) => tester
    .widgetList<SizedBox>(find.byType(SizedBox))
    .where((box) => box.width == null && box.height != null)
    .map((box) => box.height!)
    .toList();

void main() {
  group('registry dispatch', () {
    test('resolves each kind to its renderer', () {
      final registry = ElementRendererRegistry.standard();

      expect(
        registry.rendererFor(_block(ReaderElementKind.paragraph)),
        isA<ParagraphRenderer>(),
      );
      expect(
        registry.rendererFor(_block(ReaderElementKind.chapter)),
        isA<HeadingRenderer>(),
      );
      expect(
        registry.rendererFor(_block(ReaderElementKind.section)),
        isA<HeadingRenderer>(),
      );
      expect(
        registry.rendererFor(_block(ReaderElementKind.codeBlock)),
        isA<CodeBlockRenderer>(),
      );
      expect(
        registry.rendererFor(_block(ReaderElementKind.listItem)),
        isA<ListItemRenderer>(),
      );
      expect(
        registry.rendererFor(_block(ReaderElementKind.image)),
        isA<ImagePlaceholderRenderer>(),
      );
      expect(
        registry.rendererFor(_block(ReaderElementKind.table)),
        isA<TablePlaceholderRenderer>(),
      );
      expect(
        registry.rendererFor(_block(ReaderElementKind.hyperlink)),
        isA<HyperlinkRenderer>(),
      );
    });

    test('every kind resolves to something', () {
      final registry = ElementRendererRegistry.standard();

      for (final kind in ReaderElementKind.values) {
        expect(registry.rendererFor(_block(kind)), isNotNull, reason: kind.name);
      }
    });

    test('unknown kinds fall back to body text', () {
      final registry = ElementRendererRegistry.standard();

      expect(
        registry.rendererFor(_block(ReaderElementKind.unknown)),
        isA<BodyTextRenderer>(),
      );
    });

    test('an empty registry still renders through the fallback', () {
      final registry = ElementRendererRegistry();

      expect(registry.renderers, isEmpty);
      expect(
        registry.rendererFor(_block(ReaderElementKind.paragraph)),
        isA<BodyTextRenderer>(),
      );
    });

    test('registerFirst takes precedence — the Sprint 6.6 seam', () {
      final registry = ElementRendererRegistry.standard();
      const replacement = _StubRenderer(ReaderElementKind.image);

      registry.registerFirst(replacement);

      expect(
        registry.rendererFor(_block(ReaderElementKind.image)),
        same(replacement),
      );
    });

    test('register appends without displacing existing renderers', () {
      final registry = ElementRendererRegistry.standard();
      const late = _StubRenderer(ReaderElementKind.paragraph);

      registry.register(late);

      expect(
        registry.rendererFor(_block(ReaderElementKind.paragraph)),
        isA<ParagraphRenderer>(),
      );
      expect(registry.renderers.last, same(late));
    });

    test('the registered list is immutable', () {
      final registry = ElementRendererRegistry.standard();

      expect(
        () => registry.renderers.add(const BodyTextRenderer()),
        throwsUnsupportedError,
      );
    });
  });

  group('spacing ownership', () {
    testWidgets('PageBody inserts exactly one gap per adjacency', (tester) async {
      await _pump(tester, [
        _block(ReaderElementKind.paragraph, text: 'One.'),
        _block(ReaderElementKind.paragraph, text: 'Two.'),
        _block(ReaderElementKind.paragraph, text: 'Three.'),
      ]);

      // Three blocks, two gaps.
      expect(_gaps(tester), hasLength(2));
    });

    testWidgets('a single block gets no gap', (tester) async {
      await _pump(tester, [_block(ReaderElementKind.paragraph)]);

      expect(_gaps(tester), isEmpty);
    });

    testWidgets('gap heights come from BlockSpacing alone', (tester) async {
      const spacing = BlockSpacing();
      await _pump(tester, [
        _block(ReaderElementKind.chapter, title: 'Chapter One'),
        _block(ReaderElementKind.section, title: 'Foundations'),
        _block(ReaderElementKind.paragraph),
      ]);

      expect(_gaps(tester), [
        spacing.afterChapter * 16,
        spacing.afterSection * 16,
      ]);
    });

    testWidgets('heading-to-section spacing is not doubled', (tester) async {
      const spacing = BlockSpacing();
      await _pump(tester, [
        _block(ReaderElementKind.chapter, title: 'Chapter One'),
        _block(ReaderElementKind.section, title: 'Foundations'),
      ]);

      expect(_gaps(tester).single, spacing.afterChapter * 16);
      expect(
        _gaps(tester).single,
        lessThan((spacing.afterChapter + spacing.beforeSection) * 16),
      );
    });

    testWidgets('no renderer contributes vertical space of its own', (
      tester,
    ) async {
      // With a zero spacing policy, consecutive blocks must touch exactly. Any
      // margin added by a renderer would open a gap that BlockSpacing does not
      // own — which is the violation this test exists to catch.
      const noSpacing = BlockSpacing(
        paragraphGap: 0,
        beforeChapter: 0,
        afterChapter: 0,
        beforeSection: 0,
        afterSection: 0,
        setApartGap: 0,
        tightGap: 0,
      );
      await _pump(tester, [
        _block(ReaderElementKind.paragraph, text: 'First.'),
        _block(ReaderElementKind.paragraph, text: 'Second.'),
        _block(ReaderElementKind.listItem, text: 'Item', marker: BlockMarker.bullet),
      ], spacing: noSpacing);

      final first = tester.getRect(find.text('First.'));
      final second = tester.getRect(find.text('Second.'));
      final item = tester.getRect(find.text('Item'));

      expect(second.top, closeTo(first.bottom, 0.01));
      expect(item.top, closeTo(second.bottom, 0.01));
      expect(_gaps(tester), isEmpty);
    });

    testWidgets('page height is a pure function of the block sequence', (
      tester,
    ) async {
      final blocks = [
        _block(ReaderElementKind.chapter, title: 'Chapter One'),
        _block(ReaderElementKind.paragraph),
        _block(ReaderElementKind.codeBlock, text: 'SELECT 1;'),
        _block(ReaderElementKind.paragraph),
      ];

      await _pump(tester, blocks);
      final first = tester.getSize(find.byType(Column)).height;
      await _pump(tester, blocks);
      final second = tester.getSize(find.byType(Column)).height;

      expect(second, first);
    });
  });

  group('renderer output', () {
    testWidgets('paragraph renders its text as body copy', (tester) async {
      await _pump(tester, [
        _block(ReaderElementKind.paragraph, text: 'Reading comes first.'),
      ]);

      expect(find.text('Reading comes first.'), findsOneWidget);
    });

    testWidgets('chapter is more prominent than section, both above body', (
      tester,
    ) async {
      await _pump(tester, [
        _block(ReaderElementKind.chapter, title: 'Chapter One', text: 'Chapter One'),
        _block(ReaderElementKind.section, title: 'Foundations', text: 'Foundations'),
        _block(ReaderElementKind.paragraph, text: 'Body.'),
      ]);

      final chapter = tester.widget<Text>(find.text('Chapter One'));
      final section = tester.widget<Text>(find.text('Foundations'));
      final body = tester.widget<Text>(find.text('Body.'));

      expect(chapter.style!.fontSize, greaterThan(section.style!.fontSize!));
      expect(section.style!.fontSize, greaterThan(body.style!.fontSize!));
      expect(chapter.style!.fontWeight, FontWeight.w700);
    });

    testWidgets('an untitled heading renders nothing', (tester) async {
      await _pump(tester, [_block(ReaderElementKind.chapter, text: '')]);

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('code preserves whitespace and never wraps', (tester) async {
      const code = 'def explain(word):\n    return model.ask(word)';
      await _pump(tester, [_block(ReaderElementKind.codeBlock, text: code)]);

      final text = tester.widget<Text>(find.textContaining('def explain'));
      expect(text.data, code);
      expect(text.data, contains('\n    '));
      expect(text.softWrap, isFalse);
      expect(text.style!.fontFamily, 'monospace');
      // Long lines scroll instead of altering layout.
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('quote is italic with a rule and optional attribution', (
      tester,
    ) async {
      await _pump(tester, [
        _block(
          ReaderElementKind.quote,
          text: 'A book is a mirror.',
          element: const QuoteElement(
            id: 'q',
            parentId: 'sec',
            orderIndex: 0,
            sequence: 0,
            attribution: 'Lichtenberg',
          ),
        ),
      ]);

      final quote = tester.widget<Text>(find.text('A book is a mirror.'));
      expect(quote.style!.fontStyle, FontStyle.italic);
      expect(find.text('— Lichtenberg'), findsOneWidget);
    });

    testWidgets('list items show bullets and numbers', (tester) async {
      await _pump(tester, [
        _block(
          ReaderElementKind.listItem,
          text: 'First',
          marker: BlockMarker.bullet,
          depth: 1,
        ),
        _block(
          ReaderElementKind.listItem,
          text: 'Second',
          marker: BlockMarker.number,
          markerNumber: 4,
          depth: 1,
        ),
      ]);

      expect(find.text('\u2022'), findsOneWidget);
      expect(find.text('4.'), findsOneWidget);
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('nested list items indent further', (tester) async {
      await _pump(tester, [
        _block(
          ReaderElementKind.listItem,
          text: 'Nested',
          marker: BlockMarker.bullet,
          depth: 3,
        ),
      ]);

      final padding = tester.widget<Padding>(
        find
            .ancestor(
              of: find.text('Nested'),
              matching: find.byType(Padding),
            )
            .last,
      );
      expect((padding.padding as EdgeInsets).left, greaterThan(0));
    });

    testWidgets('formula renders its preserved representation verbatim', (
      tester,
    ) async {
      await _pump(tester, [
        _block(
          ReaderElementKind.formula,
          text: 'E = mc^2',
          element: const FormulaElement(
            id: 'f',
            parentId: 'sec',
            orderIndex: 0,
            sequence: 0,
            representation: 'E = mc^2',
          ),
        ),
      ]);

      final formula = tester.widget<Text>(find.text('E = mc^2'));
      expect(formula.style!.fontFamily, 'monospace');
      expect(formula.textAlign, TextAlign.center);
    });

    testWidgets('caption and footnote are small and de-emphasised', (
      tester,
    ) async {
      await _pump(tester, [
        _block(ReaderElementKind.paragraph, text: 'Body.'),
        _block(ReaderElementKind.caption, text: 'Figure 1. A diagram.'),
        _block(ReaderElementKind.footnote, text: '1. A note.'),
      ]);

      final body = tester.widget<Text>(find.text('Body.'));
      final caption = tester.widget<Text>(find.text('Figure 1. A diagram.'));
      final footnote = tester.widget<Text>(find.text('1. A note.'));

      expect(caption.style!.fontSize, lessThan(body.style!.fontSize!));
      expect(caption.style!.color, _palette.muted);
      expect(footnote.style!.fontSize, lessThan(body.style!.fontSize!));
      expect(footnote.style!.color, _palette.muted);
    });

    testWidgets('image placeholder shows details and fetches nothing', (
      tester,
    ) async {
      await _pump(tester, [
        _block(
          ReaderElementKind.image,
          text: '',
          element: const ImageElement(
            id: 'img',
            parentId: 'sec',
            orderIndex: 0,
            sequence: 0,
            identifier: 'sha256:1a2b3c4d5e6f7890',
            width: 200,
            height: 100,
            pageNumber: 7,
          ),
        ),
      ]);

      expect(find.text('Figure'), findsOneWidget);
      expect(find.textContaining('200×100'), findsOneWidget);
      expect(find.textContaining('page 7'), findsOneWidget);
      expect(find.textContaining('1a2b3c4d5e'), findsOneWidget);
      // No image widget of any kind is built.
      expect(find.byType(Image), findsNothing);
      expect(find.byType(DecoratedBox), findsWidgets);
    });

    testWidgets('table placeholder reports row count without a grid', (
      tester,
    ) async {
      await _pump(tester, [
        _block(
          ReaderElementKind.table,
          text: '',
          element: const TableElement(
            id: 'tbl',
            parentId: 'sec',
            orderIndex: 0,
            sequence: 0,
            rowCount: 3,
          ),
        ),
      ]);

      expect(find.textContaining('3 rows'), findsOneWidget);
      expect(find.byType(Table), findsNothing);
      expect(find.byType(GridView), findsNothing);
    });

    testWidgets('unknown blocks render their characters', (tester) async {
      await _pump(tester, [
        _block(ReaderElementKind.unknown, text: 'Future element text.'),
      ]);

      expect(find.text('Future element text.'), findsOneWidget);
    });
  });

  group('hyperlink renderer', () {
    testWidgets('renders tappable, accented text and never navigates', (
      tester,
    ) async {
      final tapped = <String>[];
      await _pump(
        tester,
        [
          _block(
            ReaderElementKind.hyperlink,
            text: 'Reference',
            element: const HyperlinkElement(
              id: 'h',
              parentId: 'sec',
              orderIndex: 0,
              sequence: 0,
              target: 'https://example.test/ref',
              label: 'Reference',
            ),
          ),
        ],
        onLinkTap: tapped.add,
      );

      final link = tester.widget<Text>(find.byType(Text));
      final span = link.textSpan! as TextSpan;
      expect(span.text, 'Reference');
      expect(span.style!.decoration, TextDecoration.underline);
      expect(span.style!.color, _palette.accent);

      await tester.tap(find.byType(Text));
      await tester.pump();

      expect(tapped, ['https://example.test/ref']);
      // Still on the same page: nothing was pushed.
      expect(find.byType(PageBody), findsOneWidget);
    });
  });

  group('stability', () {
    testWidgets('the widget tree is stable across identical rebuilds', (
      tester,
    ) async {
      final blocks = [
        _block(ReaderElementKind.chapter, title: 'Chapter One'),
        _block(ReaderElementKind.paragraph, text: 'Body.'),
        _block(ReaderElementKind.codeBlock, text: 'SELECT 1;'),
        _block(ReaderElementKind.listItem, text: 'Item', marker: BlockMarker.bullet),
      ];

      await _pump(tester, blocks);
      final first = tester
          .allWidgets
          .map((widget) => widget.runtimeType.toString())
          .toList();

      await _pump(tester, blocks);
      final second = tester
          .allWidgets
          .map((widget) => widget.runtimeType.toString())
          .toList();

      expect(second, first);
    });

    testWidgets('an empty block list renders nothing', (tester) async {
      await _pump(tester, const []);

      expect(find.byType(Column), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('the page does not scroll vertically', (tester) async {
      await _pump(tester, [
        for (var index = 0; index < 40; index++)
          _block(ReaderElementKind.paragraph, text: 'Paragraph $index.'),
      ]);

      // Only the code renderer may scroll, and horizontally; the page itself
      // never becomes a scroll view.
      expect(find.byType(ListView), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(ClipRect), findsOneWidget);
    });
  });
}

class _StubRenderer extends ElementRenderer {
  const _StubRenderer(this.kind);

  final ReaderElementKind kind;

  @override
  bool handles(RenderBlock block) => block.kind == kind;

  @override
  Widget build(BuildContext context, RenderBlock block, RenderContext render) =>
      const SizedBox.shrink();
}
