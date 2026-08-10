import 'package:flutter/widgets.dart';

import '../../../domain/reader_element.dart';
import '../element_renderer.dart';
import '../render_block.dart';

/// Renders chapter and section headings.
///
/// One class serves both tiers so their relationship stays visible in one place:
/// a chapter is the most prominent thing on a page, a section is clearly
/// subordinate to it and clearly distinct from body text.
///
/// Chapters do not force a page break in this sprint — that would change page
/// counts, which the Reader's anchors and progress depend on.
class HeadingRenderer extends KindRenderer {
  const HeadingRenderer.chapter()
    : scale = 1.55,
      weight = FontWeight.w700,
      _height = 1.15,
      super(ReaderElementKind.chapter);

  const HeadingRenderer.section()
    : scale = 1.2,
      weight = FontWeight.w600,
      _height = 1.2,
      super(ReaderElementKind.section);

  final double scale;
  final FontWeight weight;
  final double _height;

  @override
  Widget build(BuildContext context, RenderBlock block, RenderContext render) {
    // Prefer the element's title; fall back to the block's own text so a heading
    // is never blank.
    final text = (block.title ?? block.text).trim();
    if (text.isEmpty) return const SizedBox.shrink();

    return Text(
      text,
      style: render.scaled(
        factor: scale,
        weight: weight,
        color: render.colors.text,
        height: _height,
      ),
    );
  }
}
