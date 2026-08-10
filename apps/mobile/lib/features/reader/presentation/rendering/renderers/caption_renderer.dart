import 'package:flutter/widgets.dart';

import '../../../domain/reader_element.dart';
import '../element_renderer.dart';
import '../render_block.dart';

/// Renders a caption: small, de-emphasised, and visually attached to whatever it
/// describes.
///
/// The spacing policy places it tight against the block above, so an image and
/// its caption read as one unit without the renderer adding any margin itself.
class CaptionRenderer extends KindRenderer {
  const CaptionRenderer() : super(ReaderElementKind.caption);

  @override
  Widget build(BuildContext context, RenderBlock block, RenderContext render) {
    final element = block.element;
    final text = element is CaptionElement && (element.text?.isNotEmpty ?? false)
        ? element.text!
        : block.text;

    return Text(
      text.trim(),
      style: render.scaled(
        factor: 0.82,
        style: FontStyle.italic,
        color: render.colors.muted,
      ),
    );
  }
}
