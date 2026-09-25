import 'package:flutter/widgets.dart';

import '../../domain/reader_element.dart';
import 'render_block.dart';

/// Everything a renderer is allowed to know.
///
/// Deliberately narrow: typography, the reader's own text style, and a callback
/// for link taps. There is no repository, no HTTP client, no paginator, no
/// offsets to change, and no way to reach the network. A renderer draws a block
/// and nothing else.
@immutable
class RenderContext {
  const RenderContext({
    required this.bodyStyle,
    required this.colors,
    this.onLinkTap,
  });

  /// The reader's current body typography — font size, line height, family.
  final TextStyle bodyStyle;

  /// Colours for text, de-emphasised text, and block surfaces.
  final RenderPalette colors;

  /// Invoked when a hyperlink is tapped. Navigation is out of scope: the Reader
  /// acknowledges the target without leaving the page.
  final void Function(String target)? onLinkTap;

  double get fontSize => bodyStyle.fontSize ?? 16;

  /// A style derived from the body style, so every renderer stays in the
  /// reader's chosen typography instead of inventing its own.
  TextStyle scaled({
    double factor = 1,
    FontWeight? weight,
    FontStyle? style,
    Color? color,
    String? family,
    double? height,
  }) => bodyStyle.copyWith(
    fontSize: fontSize * factor,
    fontWeight: weight,
    fontStyle: style,
    color: color,
    fontFamily: family,
    height: height,
  );
}

/// Colours a renderer may use, supplied by the Reader's theme.
@immutable
class RenderPalette {
  const RenderPalette({
    required this.text,
    required this.muted,
    required this.accent,
    required this.surface,
    required this.outline,
  });

  final Color text;
  final Color muted;
  final Color accent;
  final Color surface;
  final Color outline;
}

/// Renders one kind of [RenderBlock].
///
/// Implementations must emit **no outer vertical spacing**. All inter-block
/// rhythm belongs to `BlockSpacing`, owned by `PageBody`; a renderer that adds
/// its own margin would make page height depend on two components and could
/// double a gap.
abstract class ElementRenderer {
  const ElementRenderer();

  /// Whether this renderer draws [block].
  bool handles(RenderBlock block);

  /// Build the block's widget. No outer margin, ever.
  Widget build(BuildContext context, RenderBlock block, RenderContext render);
}

/// Convenience base for renderers bound to a single element kind.
abstract class KindRenderer extends ElementRenderer {
  const KindRenderer(this.kind);

  final ReaderElementKind kind;

  @override
  bool handles(RenderBlock block) => block.kind == kind;
}
