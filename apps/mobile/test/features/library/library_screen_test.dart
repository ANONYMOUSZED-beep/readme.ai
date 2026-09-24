import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/auth/domain/auth_user.dart';
import 'package:readme_ai/features/library/domain/book.dart';
import 'package:readme_ai/features/library/domain/book_status.dart';
import 'package:readme_ai/features/library/domain/processing_report.dart';
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
    expect(find.text('Clean Architecture'), findsOneWidget);
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

  testWidgets('shows a loading indicator while the library loads', (
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
    await tester.pump(); // one frame; list fetch is still pending

    expect(find.byType(CircularProgressIndicator), findsWidgets);

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

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Upload book'));
    await tester.pumpAndSettle();

    expect(find.byType(BookCard), findsOneWidget);
  });

  testWidgets('deleting a book removes it via the detail screen', (
    tester,
  ) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository(initial: [_book()]);

    await pumpApp(tester, authRepository: auth, libraryRepository: library);

    // Open the detail screen.
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
    final library = FakeLibraryRepository()..releaseUpload = Completer<void>();
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
    expect(find.byType(BookCard), findsOneWidget);
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
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Upload book'));
    await tester.pump();

    expect(
      find.text('Uploaded file exceeds the maximum allowed size.'),
      findsOneWidget,
    );
    // Drain the snackbar's auto-dismiss timer.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('a failed book explains why and can be processed again', (
    tester,
  ) async {
    final auth = FakeAuthRepository(initialUser: _signedIn);
    addTearDown(auth.dispose);
    final library = FakeLibraryRepository(
      initial: [_book(status: BookStatus.failed)],
    );
    library.reports['b1'] = const ProcessingReport(
      completed: false,
      errorMessage: 'This PDF is password-protected and cannot be read.',
    );

    await pumpApp(tester, authRepository: auth, libraryRepository: library);
    await tester.tap(find.byType(BookCard));
    await tester.pumpAndSettle();

    expect(find.text("We couldn't prepare this book"), findsOneWidget);
    expect(
      find.text('This PDF is password-protected and cannot be read.'),
      findsOneWidget,
    );
    expect(find.text('Read'), findsNothing);

    final retry = find.widgetWithText(FilledButton, 'Try again');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(library.reprocessCalls, 1);
    expect(find.text("We couldn't prepare this book"), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Read'), findsOneWidget);
  });
}
