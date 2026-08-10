import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/reader_element.dart';
import '../element_renderer.dart';
import '../render_block.dart';

/// Renders a hyperlink as tappable, visually distinct text.
///
/// **Dormant by design in this sprint.** A hyperlink's label already appears
/// inside the surrounding paragraph's canonical text, so the composer does not
/// emit a separate block for one — printing it again would duplicate characters
/// on the page. The renderer is registered so the seam exists and is tested;
/// Sprint 6.6 introduces inline runs, after which links are drawn inside their
/// paragraph and this renderer's styling moves with them.
///
/// Tapping never navigates: it reports the target to the Reader, which
/// acknowledges it without leaving the page.
class HyperlinkRenderer extends KindRenderer {
  const HyperlinkRenderer() : super(ReaderElementKind.hyperlink);

  @override
  Widget build(BuildContext context, RenderBlock block, RenderContext render) {
    final element = block.element;
    final link = element is HyperlinkElement ? element : null;
    final label = (link?.label?.isNotEmpty ?? false)
        ? link!.label!
        : (block.text.trim().isNotEmpty ? block.text.trim() : link?.target ?? '');
    if (label.isEmpty) return const SizedBox.shrink();

    final target = link?.target;
    return Text.rich(
      TextSpan(
        text: label,
        style: render.bodyStyle.copyWith(
          color: render.colors.accent,
          decoration: TextDecoration.underline,
          decorationColor: render.colors.accent,
        ),
        recognizer: target == null
            ? null
            : (TapGestureRecognizer()
                ..onTap = () => render.onLinkTap?.call(target)),
      ),
    );
  }
}
