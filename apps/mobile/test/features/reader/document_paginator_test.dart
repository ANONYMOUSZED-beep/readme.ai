import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/presentation/pagination/document_paginator.dart';

void main() {
  testWidgets('pagination preserves every character in contiguous ranges', (
    tester,
  ) async {
    const paragraph =
        'Understanding grows when a reader can pause, question, and continue. ';
    final text = List.filled(80, paragraph).join('\n\n');
    const paginator = DocumentPaginator();

    final pages = paginator.paginate(
      text: text,
      style: const TextStyle(fontSize: 18, height: 1.6),
      pageSize: const Size(320, 420),
      textDirection: TextDirection.ltr,
    );

    expect(pages.length, greaterThan(1));
    expect(pages.first.startOffset, 0);
    expect(pages.last.endOffset, text.length);
    for (var index = 1; index < pages.length; index++) {
      expect(pages[index].startOffset, pages[index - 1].endOffset);
    }
    expect(pages.map((page) => page.text).join(), text);
  });

  testWidgets('pagination keeps a stable global anchor for every page', (
    tester,
  ) async {
    final text = List.generate(
      240,
      (index) => 'Sentence $index carries a distinct idea for the learner.',
    ).join(' ');
    const paginator = DocumentPaginator();

    final pages = paginator.paginate(
      text: text,
      style: const TextStyle(fontSize: 20, height: 1.5),
      pageSize: const Size(300, 360),
      textDirection: TextDirection.ltr,
    );

    for (final page in pages) {
      expect(text.substring(page.startOffset, page.endOffset), page.text);
    }
  });

  testWidgets('non-BMP text uses Unicode scalar anchors without broken pages', (
    tester,
  ) async {
    const text = 'A😀B😃C😄D😁E😆F😅G🤣H😂I🙂J🙃K😉L😊M😇N';
    const paginator = DocumentPaginator();

    final pages = paginator.paginate(
      text: text,
      style: const TextStyle(fontSize: 18, height: 1.2),
      pageSize: const Size(42, 24),
      textDirection: TextDirection.ltr,
    );

    expect(pages.length, greaterThan(1));
    expect(pages.first.startOffset, 0);
    expect(pages.last.endOffset, text.runes.length);
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      expect(page.text.contains('\uFFFD'), isFalse);
      expect(page.endOffset - page.startOffset, page.text.runes.length);
      if (index > 0) {
        expect(page.startOffset, pages[index - 1].endOffset);
      }
    }
    expect(pages.map((page) => page.text).join(), text);
  });

  testWidgets('active text scaler participates in page measurement', (
    tester,
  ) async {
    final text = List.filled(
      20,
      'Accessible reading must preserve every visible character. ',
    ).join();
    const paginator = DocumentPaginator();

    final normal = paginator.paginate(
      text: text,
      style: const TextStyle(fontSize: 16, height: 1.4),
      pageSize: const Size(240, 180),
      textDirection: TextDirection.ltr,
    );
    final scaled = paginator.paginate(
      text: text,
      style: const TextStyle(fontSize: 16, height: 1.4),
      pageSize: const Size(240, 180),
      textDirection: TextDirection.ltr,
      textScaler: const TextScaler.linear(2),
    );

    expect(scaled.length, greaterThan(normal.length));
    expect(scaled.map((page) => page.text).join(), text);
  });
}
