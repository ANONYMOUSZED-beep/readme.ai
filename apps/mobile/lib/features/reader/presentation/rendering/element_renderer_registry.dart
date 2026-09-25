import 'package:flutter/widgets.dart';

import 'element_renderer.dart';
import 'render_block.dart';
import 'renderers/body_text_renderer.dart';
import 'renderers/caption_renderer.dart';
import 'renderers/code_block_renderer.dart';
import 'renderers/footnote_renderer.dart';
import 'renderers/formula_renderer.dart';
import 'renderers/heading_renderer.dart';
import 'renderers/hyperlink_renderer.dart';
import 'renderers/image_placeholder_renderer.dart';
import 'renderers/list_item_renderer.dart';
import 'renderers/paragraph_renderer.dart';
import 'renderers/quote_renderer.dart';
import 'renderers/table_placeholder_renderer.dart';

/// Resolves a [RenderBlock] to the renderer that draws it.
///
/// Registration order *is* the extension mechanism: the first renderer whose
/// `handles` returns true wins, so Sprint 6.6 registers a rich image renderer
/// ahead of the placeholder and nothing else in the Reader changes. The Reader
/// itself never switches on element type — it asks the registry.
///
/// A body-text fallback is always last, so an unrecognised or future element
/// still renders its characters instead of vanishing.
class ElementRendererRegistry {
  ElementRendererRegistry({
    List<ElementRenderer>? renderers,
    ElementRenderer? fallback,
  }) : _renderers = [...?renderers],
       _fallback = fallback ?? const BodyTextRenderer();

  /// The renderers the Reader ships with, in resolution order.
  factory ElementRendererRegistry.standard() => ElementRendererRegistry(
    renderers: const [
      ParagraphRenderer(),
      HeadingRenderer.chapter(),
      HeadingRenderer.section(),
      CodeBlockRenderer(),
      QuoteRenderer(),
      ListItemRenderer(),
      FormulaRenderer(),
      CaptionRenderer(),
      FootnoteRenderer(),
      ImagePlaceholderRenderer(),
      TablePlaceholderRenderer(),
      // Registered for completeness. Dormant until Sprint 6.6 introduces inline
      // runs: a hyperlink's label lives inside its paragraph's text today, so
      // the composer does not emit a separate block for it.
      HyperlinkRenderer(),
    ],
  );

  final List<ElementRenderer> _renderers;
  final ElementRenderer _fallback;

  /// Registered renderers in resolution order.
  List<ElementRenderer> get renderers => List.unmodifiable(_renderers);

  ElementRenderer get fallback => _fallback;

  /// Registers [renderer] at the front, so it takes precedence.
  void registerFirst(ElementRenderer renderer) =>
      _renderers.insert(0, renderer);

  /// Registers [renderer] after the existing ones.
  void register(ElementRenderer renderer) => _renderers.add(renderer);

  /// The renderer for [block]; never null, thanks to the fallback.
  ElementRenderer rendererFor(RenderBlock block) {
    for (final renderer in _renderers) {
      if (renderer.handles(block)) return renderer;
    }
    return _fallback;
  }

  /// Builds [block]. The single dispatch point for page rendering.
  Widget render(
    BuildContext context,
    RenderBlock block,
    RenderContext render,
  ) => rendererFor(block).build(context, block, render);
}
