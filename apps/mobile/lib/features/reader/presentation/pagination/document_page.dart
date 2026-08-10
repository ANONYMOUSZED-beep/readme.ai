import 'package:flutter/foundation.dart';

/// A viewport-sized slice of a document with stable global character offsets.
///
/// Offsets count Unicode scalar values, matching the backend anchor contract
/// used by bookmarks, reading progress, and the Explanation Engine. A page is a
/// pure presentation artifact: it never changes the source text or its anchors.
@immutable
class DocumentPage {
  const DocumentPage({
    required this.text,
    required this.startOffset,
    required this.endOffset,
  });

  final String text;
  final int startOffset;
  final int endOffset;

  /// Whether [offset] falls within this page's canonical range.
  bool contains(int offset) => offset >= startOffset && offset < endOffset;
}
