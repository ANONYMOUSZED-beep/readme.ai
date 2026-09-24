import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/auth/domain/auth_user.dart';
import 'package:readme_ai/features/library/domain/book.dart';
import 'package:readme_ai/features/library/domain/book_status.dart';
import 'package:readme_ai/features/reader/application/reader_controller.dart';
import 'package:readme_ai/features/reader/application/reader_providers.dart';
import 'package:readme_ai/features/reader/domain/recent_read.dart';
import 'package:readme_ai/features/reader/presentation/reader_screen.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_library_repository.dart';
import '../../helpers/fake_reader_repository.dart';
import '../../helpers/pump_app.dart';

const _signedIn = AuthUser(uid: 'u1', email: 'a@b.com');

// A valid 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

Book _book(String id, String title, {bool hasCover = false}) => Book(
  id: id,
  title: title,
  originalFilename: '$title.epub',
  mimeType: 'application/epub+zip',
  fileSize: 2048,
  status: BookStatus.ready,
  uploadedAt: DateTime(2026),
  hasCover: hasCover,
);

RecentRead _read(String id, double percent) => RecentRead(
  bookId: id,
  progressPercentage: percent,
  lastReadAt: DateTime(2026),
);

void main() {
  testWidgets('continue reading shows unfinished books and opens the reader', (
    tester,
  ) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository(
      initial: [_book('b1', 'Dune'), _book('b2', 'Emma')],
    );
    final reader = FakeReaderRepository(
      recent: [_read('b1', 42), _read('b2', 100), _read('gone', 10)],
    );

    await pumpApp(
      tester,
      authRepository: auth,
      libraryRepository: library,
      readerRepository: reader,
    );

    expect(find.text('Continue reading'), findsOneWidget);
    expect(find.text('42% read'), findsOneWidget);
    // Finished books and books no longer in the library are left out.
    expect(find.text('100% read'), findsNothing);
    expect(find.text('10% read'), findsNothing);

    await tester.tap(find.text('42% read'));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  testWidgets('the shelf is hidden while searching and when empty', (
    tester,
  ) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);

    await pumpApp(
      tester,
      authRepository: auth,
      libraryRepository: FakeLibraryRepository(initial: [_book('b1', 'Dune')]),
      readerRepository: FakeReaderRepository(recent: [_read('b1', 30)]),
    );
    expect(find.text('Continue reading'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pumpAndSettle();
    expect(find.text('Continue reading'), findsNothing);
  });

  testWidgets('books with a cover show the picture', (tester) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository(
      initial: [_book('b1', 'Dune', hasCover: true), _book('b2', 'Emma')],
    );
    library.covers['b1'] = _png;

    await pumpApp(tester, authRepository: auth, libraryRepository: library);

    expect(find.bySemanticsLabel('Cover of Dune'), findsOneWidget);
    expect(find.bySemanticsLabel('Cover of Emma'), findsNothing);
  });

  test('saving progress refreshes the continue-reading shelf', () async {
    final repository = FakeReaderRepository();
    final container = ProviderContainer(
      overrides: [readerRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(recentReadingProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(recentReadingProvider.future);
    expect(repository.listRecentCalls, 1);

    await container
        .read(readerControllerProvider)
        .saveProgress(
          'b1',
          currentPosition: '10',
          progressPercentage: 5,
          readingTimeSeconds: 3,
        );
    await container.read(recentReadingProvider.future);

    expect(repository.listRecentCalls, 2);
  });

  testWidgets('the library with a shelf fits a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);

    await pumpApp(
      tester,
      authRepository: auth,
      libraryRepository: FakeLibraryRepository(
        initial: [_book('b1', 'A Remarkably Long Title For A Small Screen')],
      ),
      readerRepository: FakeReaderRepository(recent: [_read('b1', 12)]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('12% read'), findsOneWidget);
  });
}
