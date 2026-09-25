import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/auth/domain/auth_user.dart';
import 'package:readme_ai/features/library/domain/book.dart';
import 'package:readme_ai/features/library/domain/book_processing.dart';
import 'package:readme_ai/features/library/domain/book_status.dart';
import 'package:readme_ai/features/library/presentation/book_detail_screen.dart';
import 'package:readme_ai/features/library/presentation/library_screen.dart';
import 'package:readme_ai/features/library/presentation/widgets/book_card.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_file_picker.dart';
import '../../helpers/fake_library_repository.dart';
import '../../helpers/pump_app.dart';

const _signedIn = AuthUser(uid: 'u1', email: 'a@b.com');

Book _book({
  String id = 'b1',
  String title = 'Clean Architecture',
  BookStatus status = BookStatus.uploaded,
}) => Book(
  id: id,
  title: title,
  originalFilename: '$title.pdf',
  mimeType: 'application/pdf',
  fileSize: 2048,
  status: status,
  uploadedAt: DateTime(2026),
);

void main() {
  testWidgets('renders the user\'s books', (tester) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository(initial: [_book()]);

    await pumpApp(tester, authRepository: auth, libraryRepository: library);

    expect(find.byType(BookCard), findsOneWidget);
    // The title is typeset on the generated cover and captioned beneath it.
    expect(
      find.descendant(
        of: find.byType(BookCard),
        matching: find.text('Clean Architecture'),
      ),
      findsWidgets,
    );
  });

  testWidgets('shows the empty state when there are no books', (tester) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);

    await pumpApp(
      tester,
      authRepository: auth,
      libraryRepository: FakeLibraryRepository(),
    );

    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.byType(BookCard), findsNothing);
  });

  testWidgets('shows a loading skeleton while the library loads', (
    tester,
  ) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository()..releaseList = Completer<void>();

    await pumpApp(
      tester,
      authRepository: auth,
      libraryRepository: library,
      settle: false,
    );
    // Let auth resolve and route to the library; the list fetch stays pending.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const ValueKey('library-loading')), findsOneWidget);

    library.releaseList!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Your library is empty'), findsOneWidget);
  });

  testWidgets('shows an error state with retry on failure', (tester) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository()..listError = Exception('boom');

    await pumpApp(tester, authRepository: auth, libraryRepository: library);

    expect(find.text("Couldn't load your library."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('uploading a book adds it to the library', (tester) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository();
    final picker = FakeFilePicker(result: FakeFilePicker.sampleBook());

    await pumpApp(
      tester,
      authRepository: auth,
      libraryRepository: library,
      filePicker: picker,
    );
    expect(find.byType(BookCard), findsNothing);
    // An empty library offers upload in place of the floating button.
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('Upload book'));
    await tester.pumpAndSettle();

    expect(find.byType(BookCard), findsOneWidget);
  });

  testWidgets('failed documents explain recovery and cannot be opened', (
    tester,
  ) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository(
      initial: [_book(status: BookStatus.failed)],
    );

    await pumpApp(tester, authRepository: auth, libraryRepository: library);
    // The book grid starts below the day's highlights.
    await tester.ensureVisible(find.byType(BookCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BookCard));
    await tester.pumpAndSettle();

    expect(find.byType(BookDetailScreen), findsOneWidget);
    // Without a recorded reason the panel offers a retry, never "Read".
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Start reading'), findsNothing);
  });

  testWidgets('library remains stable at phone and desktop widths', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository(
      initial: [
        _book(id: 'b1'),
        _book(id: 'b2', title: 'Designing Data-Intensive Applications'),
        _book(id: 'b3', title: 'The Pragmatic Programmer'),
      ],
    );

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    await pumpApp(tester, authRepository: auth, libraryRepository: library);
    expect(tester.takeException(), isNull);
    expect(find.byType(BookCard), findsWidgets);

    tester.view.physicalSize = const Size(1440, 1000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(BookCard), findsNWidgets(3));
  });

  testWidgets('deleting a book removes it via the detail screen', (
    tester,
  ) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository(initial: [_book()]);

    await pumpApp(tester, authRepository: auth, libraryRepository: library);

    // Open the detail screen (the shelf sits below today's card).
    await tester.ensureVisible(find.byType(BookCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BookCard));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsOneWidget);

    // Trigger and confirm the delete dialog.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    // Back on the library, now empty.
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(BookCard), findsNothing);
    expect(find.text('Your library is empty'), findsOneWidget);
  });

  testWidgets('shows progress and blocks duplicate uploads while uploading', (
    tester,
  ) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    // A library with a book shows the floating upload button.
    final library = FakeLibraryRepository(initial: [_book()])
      ..releaseUpload = Completer<void>();
    final picker = FakeFilePicker(result: FakeFilePicker.sampleBook());

    await pumpApp(
      tester,
      authRepository: auth,
      libraryRepository: library,
      filePicker: picker,
    );

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Upload book'));
    await tester.pump();

    final button = find.widgetWithText(FloatingActionButton, 'Uploading…');
    expect(button, findsOneWidget);
    expect(tester.widget<FloatingActionButton>(button).onPressed, isNull);

    library.releaseUpload!.complete();
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FloatingActionButton, 'Upload book'), findsOne);
    expect(find.byType(BookCard), findsNWidgets(2));
  });

  testWidgets('a rejected upload shows the server\'s reason', (tester) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final options = RequestOptions(path: '/api/v1/books');
    final library = FakeLibraryRepository()
      ..uploadError = DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 413,
          data: {
            'error': {
              'code': 'payload_too_large',
              'message': 'Uploaded file exceeds the maximum allowed size.',
            },
          },
        ),
      );
    final picker = FakeFilePicker(result: FakeFilePicker.sampleBook());

    await pumpApp(
      tester,
      authRepository: auth,
      libraryRepository: library,
      filePicker: picker,
    );
    // An empty library offers upload in place of the floating button.
    await tester.tap(find.text('Upload book'));
    await tester.pump();

    expect(
      find.text('Uploaded file exceeds the maximum allowed size.'),
      findsOneWidget,
    );
    // Drain the snackbar's auto-dismiss timer.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('the detail screen of a failed book fits a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository(
      initial: [_book(status: BookStatus.failed)],
    );
    library.processing['b1'] = const BookProcessing(
      wordCount: 0,
      error: ProcessingError.emptyDocument,
    );

    await pumpApp(tester, authRepository: auth, libraryRepository: library);
    // On a small phone the book grid starts below the day's highlights.
    await tester.scrollUntilVisible(
      find.byType(BookCard),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byType(BookCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BookCard));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No readable text found'), findsOneWidget);
  });
}
