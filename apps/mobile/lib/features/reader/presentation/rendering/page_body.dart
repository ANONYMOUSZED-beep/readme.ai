import 'package:flutter/material.dart';

import 'block_spacing.dart';
import 'element_renderer.dart';
import 'element_renderer_registry.dart';
import 'render_block.dart';

/// Lays out one page's composed blocks, as a single selection domain.
///
/// Two responsibilities, both structural:
///
/// **Spacing.** This widget is the only contributor of vertical space between
/// blocks. It asks [BlockSpacing] for one gap per adjacency; renderers add none.
/// That single-owner rule makes page height a pure function of the block
/// sequence, so a heading followed by a section cannot double its gap and two
/// launches with identical inputs measure identically.
///
/// **Selection.** The whole page sits inside one [SelectionArea], so a drag can
/// run from a paragraph through a code block into the next paragraph and come
/// back as one contiguous selection. Per-widget selection would truncate at every
/// element boundary. The Explain action is added to the selection toolbar, in the
/// same place and with the same label as before.
///
/// It does not scroll and does not grow: pagination already decided what fits.
class PageBody extends StatefulWidget {
  const PageBody({
    required this.blocks,
    required this.registry,
    required this.renderContext,
    required this.explainLabel,
    this.onExplain,
    this.spacing = const BlockSpacing(),
    super.key,
  });

  final List<RenderBlock> blocks;
  final ElementRendererRegistry registry;
  final RenderContext renderContext;
  final BlockSpacing spacing;

  /// Label for the Explain action in the selection toolbar.
  final String explainLabel;

  /// Called with the selected text when the reader chooses Explain.
  ///
  /// The Reader converts that text into canonical offsets; the page body itself
  /// never computes offsets.
  final void Function(String selectedText)? onExplain;

  @override
  State<PageBody> createState() => _PageBodyState();
}

class _PageBodyState extends State<PageBody> {
  String? _selectedText;

  void _handleExplain() {
    final selected = _selectedText?.trim();
    if (selected == null || selected.isEmpty) return;
    widget.onExplain?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.blocks.isEmpty) return const SizedBox.shrink();

    final fontSize = widget.renderContext.fontSize;
    final children = <Widget>[];
    for (var index = 0; index < widget.blocks.length; index++) {
      final block = widget.blocks[index];
      if (index > 0) {
        // Exactly one gap per adjacency, from exactly one owner.
        final gap = widget.spacing.between(
          widget.blocks[index - 1],
          block,
          fontSize,
        );
        if (gap > 0) children.add(SizedBox(height: gap));
      }
      children.add(
        widget.registry.render(context, block, widget.renderContext),
      );
    }

    return SelectionArea(
      onSelectionChanged: (value) => _selectedText = value?.plainText,
      contextMenuBuilder: (context, state) {
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: state.contextMenuAnchors,
          buttonItems: [
            ContextMenuButtonItem(
              label: widget.explainLabel,
              onPressed: () {
                ContextMenuController.removeAny();
                _handleExplain();
              },
            ),
            ...state.contextMenuButtonItems,
          ],
        );
      },
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxHeight: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}
