import '../domain/element_window.dart';
import '../domain/reader_element.dart';
import '../domain/reader_span.dart';

/// Decoding for the structured element API.
///
/// Written by hand rather than generated, because the payload is polymorphic and
/// must be *tolerant*: an element type this build does not know becomes an
/// [UnknownElement], and a single malformed element is skipped rather than
/// failing the window. A reader must never lose a page because one element
/// arrived badly formed or newer than the app.
///
/// Text for paragraphs, code blocks, quotes, list items, footnotes and formulas
/// is intentionally absent from the wire — the client slices it from the
/// canonical text it already holds. Only non-derivable text (captions, table
/// cells, hyperlink labels) is decoded here.
abstract final class ElementWindowDecoder {
  /// Decode a window response, skipping elements that cannot be decoded.
  static ElementWindow decode(Map<String, dynamic> json) {
    final rawElements = json['elements'];
    final elements = <ReaderElement>[];
    var skipped = 0;

    if (rawElements is List) {
      for (final raw in rawElements) {
        if (raw is! Map) {
          skipped++;
          continue;
        }
        final element = _tryDecodeElement(Map<String, dynamic>.from(raw));
        if (element == null) {
          skipped++;
        } else {
          elements.add(element);
        }
      }
    }

    // Document order is authoritative and comes from the server's `sequence`.
    elements.sort((a, b) => a.sequence.compareTo(b.sequence));

    return ElementWindow(
      start: _int(json['start']) ?? 0,
      end: _int(json['end']) ?? 0,
      characterCount: _int(json['character_count']) ?? 0,
      elements: _withDerivedRowCounts(elements),
      truncated: json['truncated'] == true,
      skipped: skipped,
    );
  }

  static ReaderElement? _tryDecodeElement(Map<String, dynamic> json) {
    try {
      return _decodeElement(json);
    } on Object {
      // Isolation: this element is lost, the rest of the window survives.
      return null;
    }
  }

  static ReaderElement? _decodeElement(Map<String, dynamic> json) {
    final id = json['id'];
    final type = json['type'];
    final orderIndex = _int(json['order_index']);
    final sequence = _int(json['sequence']);
    if (id is! String || id.isEmpty || type is! String || type.isEmpty) {
      return null;
    }
    if (orderIndex == null || sequence == null) {
      return null;
    }

    final parentId = json['parent_id'] is String
        ? json['parent_id'] as String
        : null;
    final span = _span(json);
    final pageNumber = _int(json['page_number']);
    final payload = json['payload'] is Map
        ? Map<String, dynamic>.from(json['payload'] as Map)
        : const <String, dynamic>{};
    final text = json['text'] is String ? json['text'] as String : null;

    return switch (type) {
      'chapter' => ChapterElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        title: _string(payload['title']),
      ),
      'section' => SectionElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        title: _string(payload['title']),
      ),
      'paragraph' => ParagraphElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
      ),
      'code_block' => CodeBlockElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        language: _string(payload['language']),
      ),
      'quote' => QuoteElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        attribution: _string(payload['attribution']),
      ),
      'list' => ListElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        ordered: payload['ordered'] == true,
        startNumber: _int(payload['start_number']),
      ),
      'list_item' => ListItemElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
      ),
      'hyperlink' => _hyperlink(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        payload: payload,
        text: text,
      ),
      'formula' => _formula(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        payload: payload,
      ),
      'image' => _image(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        payload: payload,
      ),
      'caption' => _caption(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        payload: payload,
        text: text,
      ),
      'table' => TableElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
      ),
      'table_row' => TableRowElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
      ),
      'table_cell' => TableCellElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        isHeader: payload['is_header'] == true,
        text: text,
      ),
      'footnote' => FootnoteElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        label: _string(payload['label']),
        referenceId: _string(payload['reference_id']),
      ),
      // Forward compatibility: anything else still reaches the page as text.
      _ => UnknownElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        rawType: type,
      ),
    };
  }

  /// A hyperlink without a target is not renderable as a link; keep the text.
  static ReaderElement _hyperlink({
    required String id,
    required String? parentId,
    required int orderIndex,
    required int sequence,
    required ReaderSpan? span,
    required int? pageNumber,
    required Map<String, dynamic> payload,
    required String? text,
  }) {
    final target = _string(payload['target']);
    if (target == null) {
      return UnknownElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        rawType: 'hyperlink',
      );
    }
    return HyperlinkElement(
      id: id,
      parentId: parentId,
      orderIndex: orderIndex,
      sequence: sequence,
      span: span,
      pageNumber: pageNumber,
      target: target,
      label: text,
    );
  }

  /// A formula's value is its original representation, so it is required.
  static ReaderElement _formula({
    required String id,
    required String? parentId,
    required int orderIndex,
    required int sequence,
    required ReaderSpan? span,
    required int? pageNumber,
    required Map<String, dynamic> payload,
  }) {
    final representation = _string(payload['original_representation']);
    if (representation == null) {
      return UnknownElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        rawType: 'formula',
      );
    }
    return FormulaElement(
      id: id,
      parentId: parentId,
      orderIndex: orderIndex,
      sequence: sequence,
      span: span,
      pageNumber: pageNumber,
      representation: representation,
      representationFormat: _string(payload['representation_format']),
    );
  }

  /// An image without an identifier cannot be placed or later fetched.
  static ReaderElement _image({
    required String id,
    required String? parentId,
    required int orderIndex,
    required int sequence,
    required ReaderSpan? span,
    required int? pageNumber,
    required Map<String, dynamic> payload,
  }) {
    final identifier = _string(payload['image_identifier']);
    if (identifier == null) {
      return UnknownElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        rawType: 'image',
      );
    }
    return ImageElement(
      id: id,
      parentId: parentId,
      orderIndex: orderIndex,
      sequence: sequence,
      span: span,
      pageNumber: pageNumber,
      identifier: identifier,
      width: _double(payload['width']),
      height: _double(payload['height']),
      mediaType: _string(payload['media_type']),
      captionId: _string(payload['caption_id']),
    );
  }

  /// A caption whose target is unknown still renders, as ordinary body text.
  static ReaderElement _caption({
    required String id,
    required String? parentId,
    required int orderIndex,
    required int sequence,
    required ReaderSpan? span,
    required int? pageNumber,
    required Map<String, dynamic> payload,
    required String? text,
  }) {
    final describesId = _string(payload['describes_id']);
    if (describesId == null) {
      return UnknownElement(
        id: id,
        parentId: parentId,
        orderIndex: orderIndex,
        sequence: sequence,
        span: span,
        pageNumber: pageNumber,
        rawType: 'caption',
      );
    }
    return CaptionElement(
      id: id,
      parentId: parentId,
      orderIndex: orderIndex,
      sequence: sequence,
      span: span,
      pageNumber: pageNumber,
      describesId: describesId,
      text: text,
    );
  }

  /// Row counts are derived from delivered rows, never sent by the server.
  ///
  /// A truncated window can carry fewer rows than the table really has, so this
  /// reports what the client actually holds rather than a claim it cannot verify.
  static List<ReaderElement> _withDerivedRowCounts(
    List<ReaderElement> elements,
  ) {
    final rowsByTable = <String, int>{};
    for (final element in elements) {
      if (element is TableRowElement && element.parentId != null) {
        rowsByTable.update(
          element.parentId!,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    if (rowsByTable.isEmpty) return elements;

    return [
      for (final element in elements)
        if (element is TableElement)
          TableElement(
            id: element.id,
            parentId: element.parentId,
            orderIndex: element.orderIndex,
            sequence: element.sequence,
            span: element.span,
            pageNumber: element.pageNumber,
            rowCount: rowsByTable[element.id] ?? 0,
          )
        else
          element,
    ];
  }

  static ReaderSpan? _span(Map<String, dynamic> json) {
    final start = _int(json['start_offset']);
    final end = _int(json['end_offset']);
    if (start == null || end == null || start < 0 || end < start) return null;
    return ReaderSpan(start, end);
  }

  static int? _int(Object? value) => switch (value) {
    final int value => value,
    final double value => value.round(),
    _ => null,
  };

  static double? _double(Object? value) => switch (value) {
    final int value => value.toDouble(),
    final double value => value,
    _ => null,
  };

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
