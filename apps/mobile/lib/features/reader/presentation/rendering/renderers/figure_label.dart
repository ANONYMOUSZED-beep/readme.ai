/// Derives a figure or table label from a caption.
///
/// Books number their figures in the caption itself ("Figure 5. The pipeline"),
/// so the number is read from text the parser already extracted rather than
/// invented by the Reader. Nothing is counted or inferred: if the caption does
/// not state a number, the placeholder carries a plain label.
abstract final class FigureLabel {
  /// Words books use to introduce a numbered figure or table.
  static final RegExp _pattern = RegExp(
    r'^\s*(figures?|figs?|tables?|tbls?|images?|photos?|charts?|diagrams?'
    r'|listings?|exhibits?|plates?)'
    r'\s*\.?\s*'
    r'([0-9]+(?:[.\-\u2013][0-9]+)*|[IVXLC]+)'
    r'\s*[.:)\-\u2013\u2014]?',
    caseSensitive: false,
  );

  /// Canonical word for each family of caption prefixes.
  static const Map<String, String> _families = {
    'fig': 'Figure',
    'tab': 'Table',
    'tbl': 'Table',
    'ima': 'Image',
    'pho': 'Photo',
    'cha': 'Chart',
    'dia': 'Diagram',
    'lis': 'Listing',
    'exh': 'Exhibit',
    'pla': 'Plate',
  };

  /// A label such as `Figure 5`, or `null` when the caption states no number.
  static String? fromCaption(String? caption) {
    if (caption == null) return null;
    final match = _pattern.firstMatch(caption);
    if (match == null) return null;
    final word = match.group(1)!.toLowerCase();
    final number = match.group(2)!;
    final family = _families[word.substring(0, 3)];
    if (family == null) return null;
    return '$family $number';
  }

  /// The label to show, falling back to [fallback] when none can be derived.
  static String resolve(String? caption, {required String fallback}) =>
      fromCaption(caption) ?? fallback;
}
