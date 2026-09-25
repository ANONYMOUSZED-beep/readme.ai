/// The Reader's view of the stored Document Model.
///
/// Deliberate properties of this model:
///
/// * **Format agnostic.** Nothing here records a file format, MIME type, file
///   extension, or parser. Once a book is processed, the Reader cannot tell
///   whether it came from TXT, PDF, EPUB, DOCX, HTML, or Markdown.
/// * **Immutable with value equality.** Two elements carrying the same data are
///   equal, which is what makes composed pages comparable and rendering
///   verifiably deterministic across launches.
/// * **Sentences are absent.** Sentences are sub-spans of paragraphs with no
///   independent presentation. Excluding them keeps element volume down (the
///   911-page reference book holds ~37,000 of them) and avoids rendering the
///   same characters twice. Sentence-level meaning still lives in the backend,
///   where selection classification uses it.
/// * **Unknown types survive.** An element type this build does not recognise
///   becomes an [UnknownElement] and renders as readable body text, so a future
///   parser can ship before Reader support does.
library;

import 'package:flutter/foundation.dart';

import 'reader_span.dart';

/// Element kinds, used for renderer dispatch and spacing lookups.
///
/// There is intentionally no `sentence` member; see the library documentation.
enum ReaderElementKind {
  chapter,
  section,
  paragraph,
  codeBlock,
  quote,
  list,
  listItem,
  hyperlink,
  formula,
  image,
  caption,
  table,
  tableRow,
  tableCell,
  footnote,
  unknown,
}

/// A single element of a processed document.
@immutable
sealed class ReaderElement {
  const ReaderElement({
    required this.id,
    required this.parentId,
    required this.orderIndex,
    required this.sequence,
    this.span,
    this.pageNumber,
  });

  /// Stable, deterministic identity from the Document Model.
  final String id;

  /// Parent element identity, or the document id for top-level elements.
  final String? parentId;

  /// Order among siblings.
  final int orderIndex;

  /// Position in the document's element collection — the canonical document
  /// order, and the only ordering the Reader ever applies.
  final int sequence;

  /// Canonical range this element covers, or `null` for elements that carry no
  /// text of their own (images, hyperlinks, and empty containers).
  final ReaderSpan? span;

  /// Source page number when the origin format had one. Metadata only: it never
  /// takes part in the logical hierarchy, pagination, or progress.
  final int? pageNumber;

  ReaderElementKind get kind;

  /// Whether this element contributes readable text to the reading flow.
  ///
  /// Structural elements return `false`, which is what keeps them from producing
  /// selectable empty ranges.
  bool get isReadable => false;

  /// Fields compared for equality, extended by each subclass.
  @protected
  List<Object?> get props => [
    id,
    parentId,
    orderIndex,
    sequence,
    span,
    pageNumber,
  ];

  @override
  bool operator ==(Object other) =>
      other is ReaderElement &&
      other.runtimeType == runtimeType &&
      listEquals(other.props, props);

  @override
  int get hashCode => Object.hash(runtimeType, Object.hashAll(props));

  @override
  String toString() => '$runtimeType(id: $id, span: $span)';
}

/// A chapter: the most prominent heading in the reading flow.
final class ChapterElement extends ReaderElement {
  const ChapterElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    super.span,
    super.pageNumber,
    this.title,
  });

  final String? title;

  @override
  ReaderElementKind get kind => ReaderElementKind.chapter;

  @override
  List<Object?> get props => [...super.props, title];
}

/// A section: a heading subordinate to a chapter.
final class SectionElement extends ReaderElement {
  const SectionElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    super.span,
    super.pageNumber,
    this.title,
  });

  final String? title;

  @override
  ReaderElementKind get kind => ReaderElementKind.section;

  @override
  List<Object?> get props => [...super.props, title];
}

/// A paragraph: the primary reading surface.
final class ParagraphElement extends ReaderElement {
  const ParagraphElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    super.span,
    super.pageNumber,
  });

  @override
  ReaderElementKind get kind => ReaderElementKind.paragraph;

  @override
  bool get isReadable => true;
}

/// A code block. Its text is preserved verbatim, including whitespace.
final class CodeBlockElement extends ReaderElement {
  const CodeBlockElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    super.span,
    super.pageNumber,
    this.language,
  });

  /// Reported by the parser when known. Never used to highlight or tokenize.
  final String? language;

  @override
  ReaderElementKind get kind => ReaderElementKind.codeBlock;

  @override
  bool get isReadable => true;

  @override
  List<Object?> get props => [...super.props, language];
}

/// A block quote.
final class QuoteElement extends ReaderElement {
  const QuoteElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    super.span,
    super.pageNumber,
    this.attribution,
  });

  final String? attribution;

  @override
  ReaderElementKind get kind => ReaderElementKind.quote;

  @override
  bool get isReadable => true;

  @override
  List<Object?> get props => [...super.props, attribution];
}

/// A list container. Carries no text of its own; its items do.
final class ListElement extends ReaderElement {
  const ListElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    super.span,
    super.pageNumber,
    this.ordered = false,
    this.startNumber,
  });

  final bool ordered;
  final int? startNumber;

  @override
  ReaderElementKind get kind => ReaderElementKind.list;

  @override
  List<Object?> get props => [...super.props, ordered, startNumber];
}

/// One item of a list.
final class ListItemElement extends ReaderElement {
  const ListItemElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    super.span,
    super.pageNumber,
  });

  @override
  ReaderElementKind get kind => ReaderElementKind.listItem;

  @override
  bool get isReadable => true;
}

/// A hyperlink annotation. Carries no canonical span: its label already appears
/// in the surrounding text, so giving it a span would duplicate characters.
final class HyperlinkElement extends ReaderElement {
  const HyperlinkElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    required this.target,
    super.span,
    super.pageNumber,
    this.label,
  });

  final String target;
  final String? label;

  @override
  ReaderElementKind get kind => ReaderElementKind.hyperlink;

  @override
  List<Object?> get props => [...super.props, target, label];
}

/// A formula, preserved exactly as the source expressed it.
final class FormulaElement extends ReaderElement {
  const FormulaElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    required this.representation,
    super.span,
    super.pageNumber,
    this.representationFormat,
  });

  /// The original representation. Never interpreted, evaluated, or typeset.
  final String representation;
  final String? representationFormat;

  @override
  ReaderElementKind get kind => ReaderElementKind.formula;

  @override
  bool get isReadable => true;

  @override
  List<Object?> get props => [
    ...super.props,
    representation,
    representationFormat,
  ];
}

/// An image, described but never fetched or decoded in this sprint.
final class ImageElement extends ReaderElement {
  const ImageElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    required this.identifier,
    super.span,
    super.pageNumber,
    this.width,
    this.height,
    this.mediaType,
    this.captionId,
  });

  /// Stable content identifier produced by the parser (e.g. `sha256:…`).
  final String identifier;
  final double? width;
  final double? height;
  final String? mediaType;
  final String? captionId;

  @override
  ReaderElementKind get kind => ReaderElementKind.image;

  @override
  List<Object?> get props => [
    ...super.props,
    identifier,
    width,
    height,
    mediaType,
    captionId,
  ];
}

/// A caption describing an image or table.
final class CaptionElement extends ReaderElement {
  const CaptionElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    required this.describesId,
    super.span,
    super.pageNumber,
    this.text,
  });

  final String describesId;

  /// Delivered text, used when it is not derivable from the canonical slice.
  final String? text;

  @override
  ReaderElementKind get kind => ReaderElementKind.caption;

  @override
  bool get isReadable => true;

  @override
  List<Object?> get props => [...super.props, describesId, text];
}

/// A table container.
final class TableElement extends ReaderElement {
  const TableElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    super.span,
    super.pageNumber,
    this.rowCount = 0,
  });

  final int rowCount;

  @override
  ReaderElementKind get kind => ReaderElementKind.table;

  @override
  List<Object?> get props => [...super.props, rowCount];
}

/// One row of a table. Its span is the union of its cells.
final class TableRowElement extends ReaderElement {
  const TableRowElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    super.span,
    super.pageNumber,
  });

  @override
  ReaderElementKind get kind => ReaderElementKind.tableRow;

  @override
  List<Object?> get props => [...super.props];
}

/// One cell of a table row.
final class TableCellElement extends ReaderElement {
  const TableCellElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    super.span,
    super.pageNumber,
    this.isHeader = false,
    this.text,
  });

  final bool isHeader;
  final String? text;

  @override
  ReaderElementKind get kind => ReaderElementKind.tableCell;

  @override
  bool get isReadable => true;

  @override
  List<Object?> get props => [...super.props, isHeader, text];
}

/// A footnote.
final class FootnoteElement extends ReaderElement {
  const FootnoteElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    super.span,
    super.pageNumber,
    this.label,
    this.referenceId,
  });

  final String? label;
  final String? referenceId;

  @override
  ReaderElementKind get kind => ReaderElementKind.footnote;

  @override
  bool get isReadable => true;

  @override
  List<Object?> get props => [...super.props, label, referenceId];
}

/// An element type this build does not recognise.
///
/// It keeps its raw type for diagnostics and renders as body text from its span,
/// so a document produced by a newer parser never breaks reading.
final class UnknownElement extends ReaderElement {
  const UnknownElement({
    required super.id,
    required super.parentId,
    required super.orderIndex,
    required super.sequence,
    required this.rawType,
    super.span,
    super.pageNumber,
  });

  final String rawType;

  @override
  ReaderElementKind get kind => ReaderElementKind.unknown;

  /// Readable so its characters still reach the page.
  @override
  bool get isReadable => true;

  @override
  List<Object?> get props => [...super.props, rawType];
}
