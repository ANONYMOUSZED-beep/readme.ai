import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/domain/reader_element.dart';
import 'package:readme_ai/features/reader/domain/reader_span.dart';
import 'package:readme_ai/features/reader/presentation/rendering/element_renderer.dart';
import 'package:readme_ai/features/reader/presentation/rendering/element_renderer_registry.dart';
import 'package:readme_ai/features/reader/presentation/rendering/page_body.dart';
import 'package:readme_ai/features/reader/presentation/rendering/render_block.dart';
import 'package:readme_ai/features/reader/presentation/rendering/renderers/image_placeholder_renderer.dart';
import 'package:readme_ai/features/reader/presentation/rendering/renderers/table_placeholder_renderer.dart';

const _palette = RenderPalette(
  text: Color(0xFF101010),
  muted: Color(0xFF666666),
  accent: Color(0xFF3355FF),
  surface: Color(0xFFF3F3F3),
  outline: Color(0xFFDDDDDD),
);

const double _fontSize = 16;

RenderContext _render() => const RenderContext(
  bodyStyle: TextStyle(fontSize: _fontSize, height: 1.4),
  colors: _palette,
);

const _image = ImageElement(
  id: 'img',
  parentId: 'sec',
  orderIndex: 0,
  sequence: 0,
  identifier: 'sha256:1a2b3c4d5e6f7890abcd',
  width: 320,
  height: 180,
  mediaType: 'image/png',
  captionId: 'cap',
  pageNumber: 12,
);

RenderBlock _imageBlock({String? caption, ImageElement? element}) =>
    RenderBlock(
      kind: ReaderElementKind.image,
      visibleSpan: const ReaderSpan(100, 100),
      text: '',
      element: element ?? _image,
      caption: caption,
    );

RenderBlock _tableBlock({String? caption, int rowCount = 3}) => RenderBlock(
  kind: ReaderElementKind.table,
  visibleSpan: const ReaderSpan(200, 200),
  text: '',
  element: TableElement(
    id: 'tbl',
    parentId: 'sec',
    orderIndex: 1,
    sequence: 1,
    rowCount: rowCount,
    pageNumber: 12,
  ),
  caption: caption,
);

Future<void> _pump(
  WidgetTester tester,
  List<RenderBlock> blocks, {
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
            registry: ElementRendererRegistry.standard(),
            renderContext: _render(),
            explainLabel: 'Explain',
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('image placeholder', () {
    testWidgets('numbers itself from its caption', (tester) async {
      await _pump(tester, [_imageBlock(caption: 'Figure 5. The pipeline')]);

      expect(find.text('Figure 5'), findsOneWidget);
      // The caption itself is not redrawn here; it renders as its own block.
      expect(find.text('Figure 5. The pipeline'), findsNothing);
    });

    testWidgets('falls back to a plain label without a numbered caption', (
      tester,
    ) async {
      await _pump(tester, [_imageBlock(caption: 'An unnumbered diagram')]);

      expect(find.text('Figure'), findsOneWidget);
    });

    testWidgets('falls back when there is no caption at all', (tester) async {
      await _pump(tester, [_imageBlock()]);

      expect(find.text('Figure'), findsOneWidget);
    });

    testWidgets('shows dimensions, page and an abbreviated identifier', (
      tester,
    ) async {
      await _pump(tester, [_imageBlock(caption: 'Figure 2')]);

      expect(find.textContaining('320\u00D7180'), findsOneWidget);
      expect(find.textContaining('page 12'), findsOneWidget);
      expect(find.textContaining('1a2b3c4d5e\u2026'), findsOneWidget);
      // The full digest is never shown.
      expect(find.textContaining('1a2b3c4d5e6f7890abcd'), findsNothing);
    });

    testWidgets('omits details it does not have', (tester) async {
      await _pump(tester, [
        _imageBlock(
          element: const ImageElement(
            id: 'img',
            parentId: 'sec',
            orderIndex: 0,
            sequence: 0,
            identifier: 'sha256:deadbeefcafe',
          ),
        ),
      ]);

      expect(find.textContaining('page'), findsNothing);
      expect(find.textContaining('\u00D7'), findsNothing);
      expect(find.textContaining('deadbeefca\u2026'), findsOneWidget);
    });

    testWidgets('marks itself provisional and fetches no bytes', (
      tester,
    ) async {
      await _pump(tester, [_imageBlock(caption: 'Figure 1')]);

      expect(find.textContaining('later update'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(FadeInImage), findsNothing);
    });

    testWidgets('abbreviates identifiers of any shape', (tester) async {
      expect(
        ImagePlaceholderRenderer.shortIdentifier('sha256:1a2b3c4d5e6f'),
        '1a2b3c4d5e\u2026',
      );
      expect(ImagePlaceholderRenderer.shortIdentifier('sha256:abcd'), 'abcd');
      expect(ImagePlaceholderRenderer.shortIdentifier('shortid'), 'shortid');
    });
  });

  group('table placeholder', () {
    testWidgets('numbers itself from its caption and reports rows', (
      tester,
    ) async {
      await _pump(tester, [_tableBlock(caption: 'Table 3. Query plans')]);

      // The label and row count are one wrapping rich line.
      expect(
        find.textContaining('Table 3', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('3 rows', findRichText: true), findsOneWidget);
    });

    testWidgets('uses singular phrasing for one row', (tester) async {
      await _pump(tester, [_tableBlock(rowCount: 1)]);

      expect(find.textContaining('1 row', findRichText: true), findsOneWidget);
      expect(find.textContaining('1 rows', findRichText: true), findsNothing);
    });

    testWidgets('says nothing about rows when none arrived', (tester) async {
      await _pump(tester, [_tableBlock(rowCount: 0)]);

      expect(find.textContaining('Table', findRichText: true), findsOneWidget);
      expect(find.textContaining(' row', findRichText: true), findsNothing);
    });

    testWidgets('invents no grid', (tester) async {
      await _pump(tester, [_tableBlock(caption: 'Table 1')]);

      expect(find.byType(Table), findsNothing);
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(DataTable), findsNothing);
      expect(find.textContaining('later update'), findsOneWidget);
    });
  });

  group('placeholder sizing', () {
    testWidgets('image placeholder stays within its bounds', (tester) async {
      await _pump(tester, [_imageBlock(caption: 'Figure 5')]);

      final size = tester.getSize(find.byType(Container).first);
      expect(
        size.height,
        greaterThanOrEqualTo(
          _fontSize * ImagePlaceholderRenderer.minHeightFactor - 0.01,
        ),
      );
      expect(
        size.height,
        lessThanOrEqualTo(
          _fontSize * ImagePlaceholderRenderer.maxHeightFactor + 0.01,
        ),
      );
    });

    testWidgets('table placeholder stays within its bounds', (tester) async {
      await _pump(tester, [_tableBlock()]);

      final size = tester.getSize(find.byType(Container).first);
      expect(
        size.height,
        greaterThanOrEqualTo(
          _fontSize * TablePlaceholderRenderer.minHeightFactor - 0.01,
        ),
      );
      expect(
        size.height,
        lessThanOrEqualTo(
          _fontSize * TablePlaceholderRenderer.maxHeightFactor + 0.01,
        ),
      );
    });

    testWidgets('placeholders scale with the reader font size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 640,
              child: PageBody(
                blocks: [_imageBlock(caption: 'Figure 5')],
                registry: ElementRendererRegistry.standard(),
                explainLabel: 'Explain',
                renderContext: const RenderContext(
                  bodyStyle: TextStyle(fontSize: 24, height: 1.4),
                  colors: _palette,
                ),
              ),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(Container).first);
      expect(
        size.height,
        greaterThanOrEqualTo(
          24 * ImagePlaceholderRenderer.minHeightFactor - 0.01,
        ),
      );
    });

    testWidgets('neither placeholder overflows a narrow page', (tester) async {
      await _pump(tester, [
        _imageBlock(caption: 'Figure 5'),
        _tableBlock(caption: 'Table 2'),
      ], width: 200);

      expect(tester.takeException(), isNull);
    });
  });

  group('accessibility', () {
    testWidgets('image placeholder announces itself as an image', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, [_imageBlock(caption: 'Figure 5. The pipeline')]);

      expect(
        find.bySemanticsLabel(
          RegExp(r'Figure 5.*page 12.*Figure 5\. The pipeline'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('image semantics state that no preview exists yet', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, [_imageBlock()]);

      expect(
        find.bySemanticsLabel(RegExp('preview not yet available')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('table placeholder announces rows and its caption', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, [_tableBlock(caption: 'Table 3. Query plans')]);

      expect(
        find.bySemanticsLabel(RegExp(r'Table 3.*3 rows.*rows follow as text')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('decorative inner text is not announced twice', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, [_imageBlock(caption: 'Figure 5')]);

      // The visual details are excluded from semantics; one label describes all.
      expect(find.bySemanticsLabel('1a2b3c4d5e\u2026'), findsNothing);
      handle.dispose();
    });
  });

  group('determinism', () {
    testWidgets('identical blocks render identically', (tester) async {
      final blocks = [
        _imageBlock(caption: 'Figure 5. Pipeline'),
        _tableBlock(caption: 'Table 2. Plans'),
      ];

      await _pump(tester, blocks);
      final first = tester.allWidgets
          .map((w) => w.runtimeType.toString())
          .toList();
      final firstHeight = tester.getSize(find.byType(Column).first).height;

      await _pump(tester, blocks);
      final second = tester.allWidgets
          .map((w) => w.runtimeType.toString())
          .toList();
      final secondHeight = tester.getSize(find.byType(Column).first).height;

      expect(second, first);
      expect(secondHeight, firstHeight);
    });
  });

  group('unknown element polish', () {
    testWidgets('renders as ordinary prose, not as a marked gap', (
      tester,
    ) async {
      await _pump(tester, [
        const RenderBlock(
          kind: ReaderElementKind.unknown,
          visibleSpan: ReaderSpan(0, 20),
          text: 'Content from a newer parser.',
        ),
      ]);

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.data, 'Content from a newer parser.');
      expect(text.style!.color, _palette.text);
      expect(text.style!.fontSize, _fontSize);
      expect(text.style!.fontStyle, isNot(FontStyle.italic));
    });

    testWidgets('a whitespace-only block renders nothing at all', (
      tester,
    ) async {
      await _pump(tester, [
        const RenderBlock(
          kind: ReaderElementKind.unknown,
          visibleSpan: ReaderSpan(0, 3),
          text: '   \n\n  ',
        ),
      ]);

      expect(find.byType(Text), findsNothing);
    });
  });
}
