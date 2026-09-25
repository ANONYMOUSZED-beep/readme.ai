import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/auth/domain/auth_user.dart';
import 'package:readme_ai/features/library/application/library_controller.dart';
import 'package:readme_ai/features/library/domain/book.dart';
import 'package:readme_ai/features/library/domain/book_processing.dart';
import 'package:readme_ai/features/library/domain/book_status.dart';
import 'package:readme_ai/features/library/presentation/widgets/book_card.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_file_picker.dart';
import '../../helpers/fake_library_repository.dart';
import '../../helpers/pump_app.dart';

const _signedIn = AuthUser(uid: 'u1', email: 'a@b.com');

Book _book({BookStatus status = BookStatus.ready}) => Book(
  id: 'b1',
  title: 'Clean Architecture',
  originalFilename: 'Clean Architecture.txt',
  mimeType: 'text/plain',
  fileSize: 2048,
  status: status,
  uploadedAt: DateTime(2026),
);

/// Pump frames without settling (spinners animate indefinitely).
Future<void> _advance(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openDetail(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(BookCard));
  await _advance(tester);
  await tester.tap(find.byType(BookCard));
  await _advance(tester, 8);
}

void main() {
  testWidgets('upload shows its progress, then the new book', (tester) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository()..releaseUpload = Completer<void>();

    await pumpApp(
      tester,
      authRepository: auth,
      libraryRepository: library,
      filePicker: FakeFilePicker(result: FakeFilePicker.sampleBook()),
    );
    await tester.tap(find.text('Upload book'));
    await _advance(tester, 3);

    expect(find.text('Uploading sample.pdf'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);

    library.releaseUpload!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Uploading sample.pdf'), findsNothing);
    expect(find.byType(BookCard), findsOneWidget);
  });

  testWidgets('a book being prepared updates on its own once ready', (
    tester,
  ) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository(
      initial: [_book(status: BookStatus.processing)],
    )..readyAfterListCalls = 1;

    await pumpApp(
      tester,
      authRepository: auth,
      libraryRepository: library,
      settle: false,
    );
    await _advance(tester);
    expect(find.text('Preparing to read…'), findsOneWidget);

    // The library checks back without the user refreshing.
    await tester.pump(LibraryController.pollInterval);
    await tester.pumpAndSettle();

    expect(find.text('Preparing to read…'), findsNothing);
    expect(find.text('TXT · 2.0 KB'), findsOneWidget);
    expect(library.listCalls, greaterThan(1));
  });

  testWidgets('the detail screen waits while a book is prepared', (
    tester,
  ) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);

    await pumpApp(
      tester,
      authRepository: auth,
      libraryRepository: FakeLibraryRepository(
        initial: [_book(status: BookStatus.processing)],
      ),
      settle: false,
    );
    await _advance(tester);
    await _openDetail(tester);

    expect(find.text('Preparing your book…'), findsOneWidget);
    expect(find.text('Start reading'), findsNothing);
  });

  testWidgets('an unsupported format explains itself without a retry', (
    tester,
  ) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository(
      initial: [_book(status: BookStatus.failed)],
    );
    library.processing['b1'] = const BookProcessing(
      wordCount: 0,
      error: ProcessingError.unsupportedFormat,
    );

    await pumpApp(tester, authRepository: auth, libraryRepository: library);
    await _openDetail(tester);
    await tester.pumpAndSettle();

    expect(find.text("This format isn't supported"), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a transient failure can be retried', (tester) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository(
      initial: [_book(status: BookStatus.failed)],
    );
    library.processing['b1'] = const BookProcessing(
      wordCount: 0,
      error: ProcessingError.internal,
    );

    await pumpApp(tester, authRepository: auth, libraryRepository: library);
    await _openDetail(tester);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(library.retried, ['b1']);
    expect(find.text('Start reading'), findsOneWidget);
  });
}
