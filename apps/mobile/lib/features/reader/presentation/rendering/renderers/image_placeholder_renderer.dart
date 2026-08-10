import 'package:flutter/widgets.dart';

import '../../../domain/reader_element.dart';
import '../element_renderer.dart';
import '../render_block.dart';
import 'figure_label.dart';

/// Renders a bounded, provisional placeholder for an image.
///
/// No image bytes are requested, decoded, cached or displayed in this sprint.
/// The placeholder marks that a figure exists at this point in the reading flow
/// and describes it from data the parser already produced: its caption's number,
/// its dimensions, its source page, and its stable identifier.
///
/// Its caption is *not* redrawn here — the caption renders as its own block
/// immediately below, tight against this one, so the words appear exactly once.
///
/// Sprint 6.6 registers a real image renderer ahead of this one; nothing else in
/// the Reader changes.
class ImagePlaceholderRenderer extends KindRenderer {
  const ImagePlaceholderRenderer() : super(ReaderElementKind.image);

  /// Height bounds, in multiples of the reader's font size. A placeholder must
  /// be recognisable without dominating the page.
  static const double minHeightFactor = 4.5;
  static const double maxHeightFactor = 10;

  @override
  Widget build(BuildContext context, RenderBlock block, RenderContext render) {
    final element = block.element;
    final image = element is ImageElement ? element : null;
    final label = FigureLabel.resolve(block.caption, fallback: 'Figure');
    final details = _details(image);
    final fontSize = render.fontSize;

    return Semantics(
      image: true,
      label: _semanticLabel(label, image, block.caption),
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            minHeight: fontSize * minHeightFactor,
            maxHeight: fontSize * maxHeightFactor,
          ),
          decoration: BoxDecoration(
            color: render.colors.surface,
            borderRadius: BorderRadius.circular(fontSize * 0.4),
            border: Border.all(color: render.colors.outline),
          ),
          padding: EdgeInsets.all(fontSize * 0.7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Glyph(render: render, symbol: '\u25A3'),
              SizedBox(width: fontSize * 0.7),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: render.scaled(
                        factor: 0.92,
                        weight: FontWeight.w700,
                        color: render.colors.text,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: fontSize * 0.2),
                        child: Text(
                          details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: render.scaled(
                            factor: 0.75,
                            color: render.colors.muted,
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.only(top: fontSize * 0.2),
                      child: Text(
                        'Image preview arrives in a later update.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: render.scaled(
                          factor: 0.72,
                          style: FontStyle.italic,
                          color: render.colors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What a screen reader announces: what it is, where it is, and its caption.
  String _semanticLabel(String label, ImageElement? image, String? caption) {
    final parts = <String>[label];
    if (image?.pageNumber != null) parts.add('page ${image!.pageNumber}');
    if (caption != null && caption.isNotEmpty) parts.add(caption);
    parts.add('image preview not yet available');
    return parts.join('. ');
  }

  String _details(ImageElement? image) {
    if (image == null) return '';
    final parts = <String>[];
    if (image.width != null && image.height != null) {
      parts.add('${image.width!.round()}\u00D7${image.height!.round()}');
    }
    if (image.pageNumber != null) parts.add('page ${image.pageNumber}');
    parts.add(shortIdentifier(image.identifier));
    return parts.join(' \u00B7 ');
  }

  /// Abbreviates `sha256:1a2b3c…` so the identifier is visible but not shouty.
  static String shortIdentifier(String identifier) {
    final separator = identifier.indexOf(':');
    final digest = separator == -1
        ? identifier
        : identifier.substring(separator + 1);
    return digest.length <= 10 ? digest : '${digest.substring(0, 10)}\u2026';
  }
}

/// A small square glyph standing in for the artwork.
class _Glyph extends StatelessWidget {
  const _Glyph({required this.render, required this.symbol});

  final RenderContext render;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final size = render.fontSize * 2.2;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: render.colors.outline,
        borderRadius: BorderRadius.circular(render.fontSize * 0.3),
      ),
      child: Text(
        symbol,
        style: render.scaled(factor: 1.1, color: render.colors.muted),
      ),
    );
  }
}
