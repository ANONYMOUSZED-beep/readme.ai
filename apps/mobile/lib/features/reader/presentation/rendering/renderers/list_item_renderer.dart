import 'package:flutter/widgets.dart';

import '../../../domain/reader_element.dart';
import '../element_renderer.dart';
import '../render_block.dart';

/// Renders one list item with its marker.
///
/// The marker comes from the composer, which read it from the list's own
/// ordering — a bullet for unordered lists, a sequential number for ordered
/// ones. Nesting is expressed as indentation from the block's depth.
class ListItemRenderer extends KindRenderer {
  const ListItemRenderer() : super(ReaderElementKind.listItem);

  @override
  Widget build(BuildContext context, RenderBlock block, RenderContext render) {
    final marker = switch (block.marker) {
      BlockMarker.number => '${block.markerNumber ?? 1}.',
      BlockMarker.bullet => '\u2022',
      BlockMarker.none => '',
    };
    final indent =
        render.fontSize * (block.depth > 1 ? (block.depth - 1) * 1.2 : 0);

    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: render.fontSize * 1.5,
            child: Text(
              marker,
              style: render.bodyStyle.copyWith(color: render.colors.muted),
            ),
          ),
          Expanded(
            child: Text(
              block.text.trim(),
              style: render.bodyStyle.copyWith(color: render.colors.text),
            ),
          ),
        ],
      ),
    );
  }
}
