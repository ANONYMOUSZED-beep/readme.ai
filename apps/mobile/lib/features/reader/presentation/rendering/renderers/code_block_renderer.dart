import 'package:flutter/widgets.dart';

import '../../../domain/reader_element.dart';
import '../element_renderer.dart';
import '../render_block.dart';

/// Renders a code block: monospaced, verbatim, visually set apart.
///
/// The text is drawn exactly as stored — line breaks and leading whitespace
/// intact, never re-indented, reformatted, tokenized, or syntax-highlighted.
/// Long lines scroll horizontally rather than wrapping, so code stays readable
/// without affecting pagination, which was decided over canonical text before
/// this renderer ever ran.
class CodeBlockRenderer extends KindRenderer {
  const CodeBlockRenderer() : super(ReaderElementKind.codeBlock);

  @override
  Widget build(BuildContext context, RenderBlock block, RenderContext render) {
    // Only trailing blank space is dropped; internal whitespace is untouched.
    final code = _trimBlankEdges(block.text);
    final style = render.scaled(
      factor: 0.86,
      family: 'monospace',
      color: render.colors.text,
      height: 1.35,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: render.colors.surface,
        border: Border(
          left: BorderSide(color: render.colors.outline, width: 3),
        ),
      ),
      // Inner padding is part of the block's own appearance, not inter-block
      // rhythm, so it does not violate the single-owner spacing rule.
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: render.fontSize * 0.6,
          vertical: render.fontSize * 0.45,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(code, style: style, softWrap: false),
        ),
      ),
    );
  }

  /// Removes blank leading and trailing lines without touching indentation.
  String _trimBlankEdges(String code) {
    final lines = code.split('\n');
    var start = 0;
    var end = lines.length;
    while (start < end && lines[start].trim().isEmpty) {
      start++;
    }
    while (end > start && lines[end - 1].trim().isEmpty) {
      end--;
    }
    return lines.sublist(start, end).join('\n');
  }
}
