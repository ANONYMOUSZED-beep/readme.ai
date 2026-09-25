import 'package:flutter/widgets.dart';

import '../../../domain/reader_element.dart';
import '../element_renderer.dart';
import '../render_block.dart';
import 'figure_label.dart';

/// Renders a bounded, provisional placeholder for a table.
///
/// It marks that a table exists here, names it from its caption when the caption
/// numbers it, and reports how many rows arrived. It invents no column widths,
/// borders, alignment or grid — the table's own cell text follows as ordinary
/// blocks in stored row and cell order, so the content stays readable while the
/// layout waits for Sprint 6.6.
class TablePlaceholderRenderer extends KindRenderer {
  const TablePlaceholderRenderer() : super(ReaderElementKind.table);

  static const double minHeightFactor = 3.2;
  static const double maxHeightFactor = 6.5;

  @override
  Widget build(BuildContext context, RenderBlock block, RenderContext render) {
    final element = block.element;
    final rowCount = element is TableElement ? element.rowCount : 0;
    final label = FigureLabel.resolve(block.caption, fallback: 'Table');
    final rows = _rowSummary(rowCount);
    final fontSize = render.fontSize;

    return Semantics(
      label: _semanticLabel(label, rows, block.caption),
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
          padding: EdgeInsets.all(fontSize * 0.65),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // One rich line rather than a Row, so a narrow page wraps instead
              // of overflowing.
              Text.rich(
                TextSpan(
                  text: label,
                  style: render.scaled(
                    factor: 0.92,
                    weight: FontWeight.w700,
                    color: render.colors.text,
                  ),
                  children: [
                    if (rows.isNotEmpty)
                      TextSpan(
                        text: ' \u00B7 $rows',
                        style: render.scaled(
                          factor: 0.8,
                          color: render.colors.muted,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Padding(
                padding: EdgeInsets.only(top: fontSize * 0.2),
                child: Text(
                  'Rows follow as text; full layout arrives in a later update.',
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
      ),
    );
  }

  /// Row counts describe what actually arrived, never a claim about the source.
  String _rowSummary(int rowCount) {
    if (rowCount <= 0) return '';
    return rowCount == 1 ? '1 row' : '$rowCount rows';
  }

  String _semanticLabel(String label, String rows, String? caption) {
    final parts = <String>[label];
    if (rows.isNotEmpty) parts.add(rows);
    if (caption != null && caption.isNotEmpty) parts.add(caption);
    parts.add('table layout not yet available; rows follow as text');
    return parts.join('. ');
  }
}
