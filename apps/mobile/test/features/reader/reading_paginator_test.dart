import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/domain/pagination_source.dart';
import 'package:readme_ai/features/reader/presentation/pagination/reading_paginator.dart';

ReadingPaginator _paginatorFor(String text) {
  return ReadingPaginator(
    source: StringPaginationSource(text),
    style: const TextStyle(fontSize: 18, height: 1.6),
    pageSize: const Size(320, 420),
    textDirection: TextDirection.ltr,
  );
}

void main() {
  final largeText = List.filled(
    4000,
    'Understanding grows when a reader can pause, question, and continue. ',
  ).join('\n\n');

  testWidgets('first page is available without paginating the whole document', (
    tester,
  ) async {
    final paginator = _paginatorFor(largeText);
    addTearDown(paginator.dispose);

    await tester.runAsync(() => paginator.ensureIndex(0));

    expect(paginator.hasFirstPage, isTrue);
    expect(paginator.isComplete, isFalse);
    // Only a handful of pages were measured, not the whole book.
    expect(paginator.pageCount, lessThan(20));
    expect(paginator.estimatedTotalPages, greaterThan(paginator.pageCount));
  });

  testWidgets('ensureOffset measures only up to the requested position', (
    tester,
  ) async {
    final paginator = _paginatorFor(largeText);
    addTearDown(paginator.dispose);
    final source = StringPaginationSource(largeText);
    final targetOffset = source.length ~/ 10; // ~10% into the book

    late final int index;
    await tester.runAsync(() async {
      index = await paginator.ensureOffset(targetOffset);
    });

    expect(paginator.pageAt(index).contains(targetOffset), isTrue);
    expect(paginator.isComplete, isFalse);
    // The window reached the target without paginating the entire document.
    expect(
      paginator.pageAt(paginator.pageCount - 1).endOffset,
      lessThan(source.length),
    );
  });

  testWidgets('pages remain contiguous and cached across incremental growth', (
    tester,
  ) async {
    final paginator = _paginatorFor(largeText);
    addTearDown(paginator.dispose);

    await tester.runAsync(() => paginator.ensureIndex(3));
    final firstBatch = paginator.pageCount;
    await tester.runAsync(() => paginator.ensureIndex(8));

    expect(paginator.pageCount, greaterThanOrEqualTo(firstBatch));
    for (var i = 1; i < paginator.pageCount; i++) {
      expect(
        paginator.pageAt(i).startOffset,
        paginator.pageAt(i - 1).endOffset,
      );
    }
  });

  testWidgets('small documents complete with a single reading window', (
    tester,
  ) async {
    final paginator = _paginatorFor('A short paragraph that fits one page.');
    addTearDown(paginator.dispose);

    await tester.runAsync(() => paginator.ensureIndex(0));

    expect(paginator.hasFirstPage, isTrue);
    expect(paginator.isComplete, isTrue);
    expect(paginator.pageCount, 1);
  });
}
