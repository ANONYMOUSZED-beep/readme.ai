import 'package:flutter/widgets.dart';

import '../element_renderer.dart';
import '../render_block.dart';

/// Renders any block as plain body text.
///
/// The registry's fallback, and the reason structure can always be incomplete
/// without costing a word. It handles page text no element claimed, element types
/// this build does not recognise, and anything a future parser emits before the
/// Reader learns about it.
///
/// It is deliberately indistinguishable from a paragraph: a reader should never
/// see that the Reader was unsure what something was. Unrecognised content reads
/// as prose rather than announcing itself as a gap.
class BodyTextRenderer extends ElementRenderer {
  const BodyTextRenderer();

  @override
  bool handles(RenderBlock block) => true;

  @override
  Widget build(BuildContext context, RenderBlock block, RenderContext render) {
    final text = block.text.trim();
    // Whitespace-only runs would otherwise leave an empty block, and with it a
    // stray gap that BlockSpacing had no reason to add.
    if (text.isEmpty) return const SizedBox.shrink();

    // No outer padding or margin: spacing belongs to BlockSpacing alone.
    return Text(
      text,
      style: render.bodyStyle.copyWith(color: render.colors.text),
      textAlign: TextAlign.start,
    );
  }
}
