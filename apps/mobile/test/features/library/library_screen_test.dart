import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/auth/domain/auth_user.dart';
import 'package:readme_ai/features/library/domain/book.dart';
import 'package:readme_ai/features/library/domain/book_status.dart';
import 'package:readme_ai/features/library/presentation/book_detail_screen.dart';
import 'package:readme_ai/features/library/presentation/library_screen.dart';
import 'package:readme_ai/features/library/presentation/widgets/book_card.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_file_picker.dart';
import '../../helpers/fake_library_repository.dart';
import '../../helpers/pump_app.dart';

const _signedIn = AuthUser(uid: 'u1', email: 'a@b.com');

Book _book({String id = 'b1', String title = 'Clean Architecture'}) => Book(
  id: id,
  title: title,
  originalFilename: '$title.pdf',
  mimeType: 'application/pdf',
  fileSize: 2048,
  status: BookStatus.uploaded,
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
}
