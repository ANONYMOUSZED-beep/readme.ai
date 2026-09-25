import 'package:flutter/material.dart';

import '../../domain/pagination_source.dart';
import 'document_page.dart';
import 'page_measurer.dart';

export 'document_page.dart' show DocumentPage;

/// Converts logical document text into viewport-sized presentation pages.
///
/// Pagination never changes the source text or its global character anchors.
///
/// This eager, whole-document API is retained for tests and simple callers, but
/// each page is now measured with the bounded [PageMeasurer] rather than by
/// laying out the entire remaining document. The Reader itself no longer calls
/// this eagerly; it uses the incremental reading window instead (see
/// `ReadingPaginator`).
class DocumentPaginator {
  const DocumentPaginator({this.measurer = const PageMeasurer()});

  final PageMeasurer measurer;

  List<DocumentPage> paginate({
    required String text,
    required TextStyle style,
    required Size pageSize,
    required TextDirection textDirection,
    TextScaler textScaler = TextScaler.noScaling,
    Locale? locale,
  }) {
    if (text.isEmpty) return const [];
    final source = StringPaginationSource(text);

    final pages = <DocumentPage>[];
    var start = 0;
    while (start < source.length) {
      final page = measurer.measureForward(
        source: source,
        start: start,
        style: style,
        pageSize: pageSize,
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
      );
      if (page == null || page.endOffset <= start) break;
      pages.add(page);
      start = page.endOffset;
    }
    return pages;
  }
}
