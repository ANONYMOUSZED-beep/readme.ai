import '../../domain/reader_element.dart';
import 'render_block.dart';

/// The single owner of vertical rhythm between blocks.
///
/// This class exists to make page height a pure function of the block sequence.
/// Renderers contribute **zero** outer spacing; every gap on a page comes from
/// here, inserted by `PageBody` between consecutive blocks only. With one owner:
///
/// * a heading followed by a section cannot double its gap, because only one
///   component is asked for the gap;
/// * the same block sequence always measures the same height, which is what
///   makes rendering deterministic across launches;
/// * spacing is a table that can be reviewed, not behaviour scattered across
///   thirteen renderers.
///
/// Gaps are expressed as multiples of the reader's font size, so rhythm scales
/// with typography instead of drifting when the reader changes text size.
class BlockSpacing {
  const BlockSpacing({
    this.paragraphGap = 0.85,
    this.beforeChapter = 1.6,
    this.afterChapter = 0.7,
    this.beforeSection = 1.25,
    this.afterSection = 0.55,
    this.setApartGap = 1.0,
    this.tightGap = 0.35,
    this.noGap = 0.0,
  });

  /// Between two body paragraphs.
  final double paragraphGap;

  /// Above a chapter heading, and below it.
  final double beforeChapter;
  final double afterChapter;

  /// Above a section heading, and below it.
  final double beforeSection;
  final double afterSection;

  /// Around visually set-apart blocks: code, quotes, formulas, placeholders.
  final double setApartGap;

  /// Between closely related blocks: list items, table cells, a caption and the
  /// image it describes, consecutive footnotes.
  final double tightGap;

  final double noGap;

  /// Vertical gap between [previous] and [next], in logical pixels.
  ///
  /// Exactly one value is returned per adjacency, so no combination of blocks
  /// can accumulate two gaps.
  double between(RenderBlock previous, RenderBlock next, double fontSize) =>
      _factor(previous, next) * fontSize;

  double _factor(RenderBlock previous, RenderBlock next) {
    // A heading's own spacing wins over whatever preceded it, so
    // heading-after-heading yields one gap rather than "after" plus "before".
    if (next.kind == ReaderElementKind.chapter) return beforeChapter;
    if (next.kind == ReaderElementKind.section) {
      // Immediately under a chapter title the section sits close, not doubled.
      return previous.kind == ReaderElementKind.chapter
          ? afterChapter
          : beforeSection;
    }
    if (previous.kind == ReaderElementKind.chapter) return afterChapter;
    if (previous.kind == ReaderElementKind.section) return afterSection;

    // A caption belongs to the thing above it.
    if (next.kind == ReaderElementKind.caption) return tightGap;
    if (_isTightPair(previous.kind, next.kind)) return tightGap;

    if (_isSetApart(previous.kind) || _isSetApart(next.kind)) {
      return setApartGap;
    }
    return paragraphGap;
  }

  bool _isTightPair(ReaderElementKind previous, ReaderElementKind next) {
    if (previous == ReaderElementKind.listItem &&
        next == ReaderElementKind.listItem) {
      return true;
    }
    if (previous == ReaderElementKind.tableCell &&
        next == ReaderElementKind.tableCell) {
      return true;
    }
    if (previous == ReaderElementKind.footnote &&
        next == ReaderElementKind.footnote) {
      return true;
    }
    return previous == ReaderElementKind.table &&
        next == ReaderElementKind.tableCell;
  }

  bool _isSetApart(ReaderElementKind kind) => switch (kind) {
    ReaderElementKind.codeBlock ||
    ReaderElementKind.quote ||
    ReaderElementKind.formula ||
    ReaderElementKind.image ||
    ReaderElementKind.table => true,
    _ => false,
  };
}
