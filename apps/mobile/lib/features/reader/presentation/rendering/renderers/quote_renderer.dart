import 'package:flutter/widgets.dart';

import '../../../domain/reader_element.dart';
import '../element_renderer.dart';
import '../render_block.dart';

/// Renders a block quote: indented, with a leading rule, in body typography.
///
/// Quotes stay in the reader's own type so they remain comfortable to read; only
/// their position and a rule mark them as quoted.
class QuoteRenderer extends KindRenderer {
  const QuoteRenderer() : super(ReaderElementKind.quote);

  @override
  Widget build(BuildContext context, RenderBlock block, RenderContext render) {
    final element = block.element;
    final attribution = element is QuoteElement ? element.attribution : null;

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: render.colors.accent, width: 3)),
      ),
      padding: EdgeInsets.only(left: render.fontSize * 0.75),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            block.text.trim(),
            style: render.bodyStyle.copyWith(
              color: render.colors.text,
              fontStyle: FontStyle.italic,
            ),
          ),
          if (attribution != null && attribution.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: render.fontSize * 0.3),
              child: Text(
                '— $attribution',
                style: render.scaled(factor: 0.85, color: render.colors.muted),
              ),
            ),
        ],
      ),
    );
  }
}
