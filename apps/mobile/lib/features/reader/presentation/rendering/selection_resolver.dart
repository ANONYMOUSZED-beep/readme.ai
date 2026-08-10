import '../../domain/character_anchor.dart';
import '../../domain/reader_span.dart';

/// Maps a page selection back to canonical scalar offsets.
///
/// Flutter's `SelectionArea` reports the selected *text*, not offsets, so the
/// resolver locates that text inside the page's own canonical slice. This works
/// because composition only clips and re-styles: every character rendered on a
/// page exists in that page's canonical text, in the same order. A selection
/// spanning a paragraph, a code block and another paragraph therefore resolves to
/// one contiguous canonical range.
///
/// Two rules keep it honest:
///
/// * **Never invent offsets.** Every returned range is a literal match inside the
///   page text; nothing is estimated or interpolated.
/// * **Prefer nothing over wrong.** If the selection cannot be located, or is
///   genuinely ambiguous with no positional hint to break the tie, the resolver
///   returns `null` and the Reader submits no explanation request.
class SelectionResolver {
  const SelectionResolver();

  /// Resolves [selectedText] within a page.
  ///
  /// [pageText] is the page's canonical slice and [pageStartOffset] its canonical
  /// start. [hintOffset] is the reader's last known position, used only to choose
  /// between identical candidate matches.
  ReaderSpan? resolve({
    required String pageText,
    required int pageStartOffset,
    required String selectedText,
    int? hintOffset,
  }) {
    if (pageText.isEmpty) return null;

    final trimmed = _trim(selectedText);
    if (trimmed.isEmpty) return null;

    final exact = _resolveExact(pageText, trimmed, hintOffset, pageStartOffset);
    if (exact != null) return exact;

    // Rendering may drop separator whitespace between blocks, so a cross-element
    // selection can differ from the canonical text by whitespace alone.
    return _resolveCollapsed(pageText, trimmed, hintOffset, pageStartOffset);
  }

  /// Trims the selection exactly as the previous implementation did, so the text
  /// submitted for explanation is unchanged.
  String _trim(String text) => text.trim();

  ReaderSpan? _resolveExact(
    String pageText,
    String selected,
    int? hintOffset,
    int pageStartOffset,
  ) {
    final matches = <int>[];
    var index = pageText.indexOf(selected);
    while (index != -1) {
      matches.add(index);
      if (matches.length > _maxCandidates) break;
      index = pageText.indexOf(selected, index + 1);
    }
    if (matches.isEmpty) return null;

    final codeUnitStart = _chooseCandidate(
      matches,
      pageText,
      hintOffset,
      pageStartOffset,
    );
    if (codeUnitStart == null) return null;

    return _toCanonical(
      pageText,
      pageStartOffset,
      codeUnitStart,
      codeUnitStart + selected.length,
    );
  }

  /// Matches on whitespace-collapsed forms, mapping the result back to the exact
  /// positions in the original page text.
  ReaderSpan? _resolveCollapsed(
    String pageText,
    String selected,
    int? hintOffset,
    int pageStartOffset,
  ) {
    final page = _collapse(pageText);
    final needle = _collapse(selected).text;
    if (needle.isEmpty) return null;

    final matches = <int>[];
    var index = page.text.indexOf(needle);
    while (index != -1) {
      matches.add(index);
      if (matches.length > _maxCandidates) break;
      index = page.text.indexOf(needle, index + 1);
    }
    if (matches.isEmpty) return null;

    final chosen = _chooseCollapsedCandidate(
      matches,
      page,
      hintOffset,
      pageStartOffset,
    );
    if (chosen == null) return null;

    final startCodeUnit = page.sources[chosen];
    // The end maps from the last matched character, so trailing collapsed
    // whitespace is never included in the range.
    final endCodeUnit = page.sources[chosen + needle.length - 1] + 1;
    return _toCanonical(pageText, pageStartOffset, startCodeUnit, endCodeUnit);
  }

  /// Chooses among identical matches, or refuses when the choice is arbitrary.
  int? _chooseCandidate(
    List<int> matches,
    String pageText,
    int? hintOffset,
    int pageStartOffset,
  ) {
    if (matches.length > _maxCandidates) return null;
    if (matches.length == 1) return matches.first;
    if (hintOffset == null) return null;

    final hintCodeUnit = CharacterAnchor.toCodeUnit(
      pageText,
      (hintOffset - pageStartOffset).clamp(
        0,
        CharacterAnchor.length(pageText),
      ),
    );
    return _nearest(matches, hintCodeUnit);
  }

  int? _chooseCollapsedCandidate(
    List<int> matches,
    _Collapsed page,
    int? hintOffset,
    int pageStartOffset,
  ) {
    if (matches.length > _maxCandidates) return null;
    if (matches.length == 1) return matches.first;
    if (hintOffset == null) return null;

    final hintCodeUnit = hintOffset - pageStartOffset;
    // Compare in collapsed space by mapping candidates back to source positions.
    var best = matches.first;
    var bestDistance = (page.sources[best] - hintCodeUnit).abs();
    for (final candidate in matches.skip(1)) {
      final distance = (page.sources[candidate] - hintCodeUnit).abs();
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  int _nearest(List<int> matches, int target) {
    var best = matches.first;
    var bestDistance = (best - target).abs();
    for (final candidate in matches.skip(1)) {
      final distance = (candidate - target).abs();
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  ReaderSpan? _toCanonical(
    String pageText,
    int pageStartOffset,
    int codeUnitStart,
    int codeUnitEnd,
  ) {
    final safeStart = codeUnitStart.clamp(0, pageText.length);
    final safeEnd = codeUnitEnd.clamp(safeStart, pageText.length);
    final start =
        pageStartOffset + CharacterAnchor.fromCodeUnit(pageText, safeStart);
    final end =
        pageStartOffset + CharacterAnchor.fromCodeUnit(pageText, safeEnd);
    if (end <= start) return null;
    return ReaderSpan(start, end);
  }

  /// Collapses whitespace runs to single spaces, keeping a map back to the
  /// original code-unit positions so a match can be reported exactly.
  _Collapsed _collapse(String text) {
    final buffer = StringBuffer();
    final sources = <int>[];
    var pendingSpace = false;

    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (_isWhitespace(char)) {
        if (buffer.isNotEmpty) pendingSpace = true;
        continue;
      }
      if (pendingSpace) {
        buffer.write(' ');
        sources.add(index);
        pendingSpace = false;
      }
      buffer.write(char);
      sources.add(index);
    }
    return _Collapsed(buffer.toString(), sources);
  }

  bool _isWhitespace(String char) =>
      char == ' ' ||
      char == '\n' ||
      char == '\t' ||
      char == '\r' ||
      char == '\u000B' ||
      char == '\u000C' ||
      char == '\u00A0' ||
      char == '\u2028' ||
      char == '\u2029';

  /// Above this many identical candidates the selection is treated as ambiguous
  /// even with a hint, because a near-miss would be indistinguishable.
  static const int _maxCandidates = 64;
}

/// A whitespace-collapsed string plus a map back to source code-unit indexes.
class _Collapsed {
  const _Collapsed(this.text, this.sources);

  final String text;
  final List<int> sources;
}
