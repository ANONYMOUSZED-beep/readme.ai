import 'package:flutter/widgets.dart';

import '../../../domain/reader_element.dart';
import '../element_renderer.dart';
import '../render_block.dart';

/// Renders a footnote: small and de-emphasised, at its position in the flow.
///
/// Its marker is shown when the parser found one. Jump-to-reference linking is
/// out of scope for this sprint.
class FootnoteRenderer extends KindRenderer {
  const FootnoteRenderer() : super(ReaderElementKind.footnote);

  @override
  Widget build(BuildContext context, RenderBlock block, RenderContext render) {
    final element = block.element;
    final label = element is FootnoteElement ? element.label : null;
    final text = block.text.trim();
    final style = render.scaled(factor: 0.8, color: render.colors.muted);

    if (label == null || label.isEmpty || text.startsWith(label)) {
      // The marker is already part of the footnote's own text.
      return Text(text, style: style);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(right: render.fontSize * 0.3),
          child: Text(
            label,
            style: style.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
