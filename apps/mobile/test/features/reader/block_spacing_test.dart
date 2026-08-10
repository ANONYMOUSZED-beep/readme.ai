import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/domain/reader_element.dart';
import 'package:readme_ai/features/reader/domain/reader_span.dart';
import 'package:readme_ai/features/reader/presentation/rendering/block_spacing.dart';
import 'package:readme_ai/features/reader/presentation/rendering/render_block.dart';

const double _fontSize = 16;

RenderBlock _block(ReaderElementKind kind) => RenderBlock(
  kind: kind,
  visibleSpan: const ReaderSpan(0, 1),
  text: kind == ReaderElementKind.image || kind == ReaderElementKind.table
      ? ''
      : 'text',
);

void main() {
  const spacing = BlockSpacing();

  double gap(ReaderElementKind previous, ReaderElementKind next) =>
      spacing.between(_block(previous), _block(next), _fontSize);

  group('single gap per adjacency', () {
    test('every adjacency yields exactly one non-negative value', () {
      for (final previous in ReaderElementKind.values) {
        for (final next in ReaderElementKind.values) {
          final value = gap(previous, next);
          expect(
            value,
            greaterThanOrEqualTo(0),
            reason: '${previous.name} -> ${next.name}',
          );
          // A single adjacency can never exceed the largest single factor, which
          // is what proves no two factors are being summed.
          expect(
            value,
            lessThanOrEqualTo(spacing.beforeChapter * _fontSize),
            reason: '${previous.name} -> ${next.name} looks doubled',
          );
        }
      }
    });

    test('heading-to-section is not the sum of after-chapter and before-section', () {
      final value = gap(ReaderElementKind.chapter, ReaderElementKind.section);

      expect(value, spacing.afterChapter * _fontSize);
      expect(
        value,
        lessThan((spacing.afterChapter + spacing.beforeSection) * _fontSize),
      );
    });

    test('section-to-section uses one heading gap, not two', () {
      final value = gap(ReaderElementKind.section, ReaderElementKind.section);

      expect(value, spacing.beforeSection * _fontSize);
      expect(
        value,
        lessThan((spacing.afterSection + spacing.beforeSection) * _fontSize),
      );
    });

    test('code-to-quote is one set-apart gap, not two', () {
      final value = gap(ReaderElementKind.codeBlock, ReaderElementKind.quote);

      expect(value, spacing.setApartGap * _fontSize);
      expect(value, lessThan(2 * spacing.setApartGap * _fontSize));
    });
  });

  group('documented adjacencies', () {
    test('heading to paragraph', () {
      expect(
        gap(ReaderElementKind.chapter, ReaderElementKind.paragraph),
        spacing.afterChapter * _fontSize,
      );
      expect(
        gap(ReaderElementKind.section, ReaderElementKind.paragraph),
        spacing.afterSection * _fontSize,
      );
    });

    test('paragraph to heading gives the heading its own space', () {
      expect(
        gap(ReaderElementKind.paragraph, ReaderElementKind.chapter),
        spacing.beforeChapter * _fontSize,
      );
      expect(
        gap(ReaderElementKind.paragraph, ReaderElementKind.section),
        spacing.beforeSection * _fontSize,
      );
    });

    test('paragraph to paragraph', () {
      expect(
        gap(ReaderElementKind.paragraph, ReaderElementKind.paragraph),
        spacing.paragraphGap * _fontSize,
      );
    });

    test('code to paragraph and paragraph to code', () {
      expect(
        gap(ReaderElementKind.codeBlock, ReaderElementKind.paragraph),
        spacing.setApartGap * _fontSize,
      );
      expect(
        gap(ReaderElementKind.paragraph, ReaderElementKind.codeBlock),
        spacing.setApartGap * _fontSize,
      );
    });

    test('quote to paragraph', () {
      expect(
        gap(ReaderElementKind.quote, ReaderElementKind.paragraph),
        spacing.setApartGap * _fontSize,
      );
    });

    test('list item to paragraph, and between list items', () {
      expect(
        gap(ReaderElementKind.listItem, ReaderElementKind.paragraph),
        spacing.paragraphGap * _fontSize,
      );
      // Items of one list sit close together.
      expect(
        gap(ReaderElementKind.listItem, ReaderElementKind.listItem),
        spacing.tightGap * _fontSize,
      );
    });

    test('a caption hugs whatever it describes', () {
      expect(
        gap(ReaderElementKind.image, ReaderElementKind.caption),
        spacing.tightGap * _fontSize,
      );
      expect(
        gap(ReaderElementKind.table, ReaderElementKind.caption),
        spacing.tightGap * _fontSize,
      );
    });

    test('table cells and consecutive footnotes stay tight', () {
      expect(
        gap(ReaderElementKind.table, ReaderElementKind.tableCell),
        spacing.tightGap * _fontSize,
      );
      expect(
        gap(ReaderElementKind.tableCell, ReaderElementKind.tableCell),
        spacing.tightGap * _fontSize,
      );
      expect(
        gap(ReaderElementKind.footnote, ReaderElementKind.footnote),
        spacing.tightGap * _fontSize,
      );
    });

    test('placeholders are set apart from body text', () {
      expect(
        gap(ReaderElementKind.paragraph, ReaderElementKind.image),
        spacing.setApartGap * _fontSize,
      );
      expect(
        gap(ReaderElementKind.paragraph, ReaderElementKind.table),
        spacing.setApartGap * _fontSize,
      );
    });

    test('unknown blocks read as body text', () {
      expect(
        gap(ReaderElementKind.paragraph, ReaderElementKind.unknown),
        spacing.paragraphGap * _fontSize,
      );
    });
  });

  group('determinism and scaling', () {
    test('the same adjacency always yields the same gap', () {
      for (final previous in ReaderElementKind.values) {
        for (final next in ReaderElementKind.values) {
          expect(gap(previous, next), gap(previous, next));
        }
      }
    });

    test('gaps scale with the reader font size', () {
      final small = spacing.between(
        _block(ReaderElementKind.paragraph),
        _block(ReaderElementKind.paragraph),
        12,
      );
      final large = spacing.between(
        _block(ReaderElementKind.paragraph),
        _block(ReaderElementKind.paragraph),
        24,
      );

      expect(large, small * 2);
    });

    test('spacing depends only on kinds, not on block content', () {
      const first = RenderBlock(
        kind: ReaderElementKind.paragraph,
        visibleSpan: ReaderSpan(0, 400),
        text: 'a very long paragraph of text',
        clipped: true,
        depth: 3,
      );
      const second = RenderBlock(
        kind: ReaderElementKind.paragraph,
        visibleSpan: ReaderSpan(400, 401),
        text: 'x',
      );

      expect(
        spacing.between(first, second, _fontSize),
        spacing.between(second, first, _fontSize),
      );
    });
  });
}
