import 'package:flutter/widgets.dart';

import '../../../domain/reader_element.dart';
import '../element_renderer.dart';
import '../render_block.dart';

/// Renders a formula as its preserved original representation.
///
/// Never interpreted, evaluated, typeset, or converted. Whatever the source
/// expressed is what the reader sees, set apart and centred so it reads as a
/// displayed formula rather than as prose.
class FormulaRenderer extends KindRenderer {
  const FormulaRenderer() : super(ReaderElementKind.formula);

  @override
  Widget build(BuildContext context, RenderBlock block, RenderContext render) {
    final element = block.element;
    // Prefer the stored representation; the block's own text is the same
    // characters, and is used when the element is not to hand.
    final representation = element is FormulaElement
        ? element.representation
        : block.text;

    return SizedBox(
      width: double.infinity,
      child: Text(
        representation.trim(),
        textAlign: TextAlign.center,
        style: render.scaled(
          factor: 0.95,
          family: 'monospace',
          color: render.colors.text,
        ),
      ),
    );
  }
}
