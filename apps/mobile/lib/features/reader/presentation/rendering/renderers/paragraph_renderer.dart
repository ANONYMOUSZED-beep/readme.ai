import 'package:flutter/widgets.dart';

import '../../../domain/reader_element.dart';
import '../element_renderer.dart';
import '../render_block.dart';

/// Renders a paragraph: the primary reading surface.
///
/// Deliberately plain. Body text must look exactly as it did when the Reader
/// rendered one flat string, so a reader notices structure elsewhere on the page
/// and nothing at all here.
class ParagraphRenderer extends KindRenderer {
  const ParagraphRenderer() : super(ReaderElementKind.paragraph);

  @override
  Widget build(BuildContext context, RenderBlock block, RenderContext render) {
    return Text(
      block.text.trim(),
      style: render.bodyStyle.copyWith(color: render.colors.text),
      textAlign: TextAlign.start,
    );
  }
}
