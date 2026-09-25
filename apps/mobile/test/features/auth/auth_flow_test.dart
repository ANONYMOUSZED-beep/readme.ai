import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/auth/domain/auth_user.dart';
import 'package:readme_ai/features/auth/presentation/login_page.dart';
import 'package:readme_ai/features/library/presentation/library_screen.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/pump_app.dart';

void main() {
  group('protected routing', () {
    testWidgets('signed-out users land on login', (tester) async {
      final repository = FakeAuthRepository();
      addTearDown(repository.dispose);

      await pumpApp(tester, authRepository: repository);

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(LibraryScreen), findsNothing);
    });

    testWidgets('signed-in users land on the library', (tester) async {
      final repository = FakeAuthRepository(
        initialUser: const AuthUser(uid: 'u1', email: 'a@b.com'),
      );
      addTearDown(repository.dispose);

      await pumpApp(tester, authRepository: repository);

      expect(find.byType(LibraryScreen), findsOneWidget);
    });
  });

  group('authentication flow', () {
    testWidgets('signing in navigates from login to the library', (
      tester,
    ) async {
      final repository = FakeAuthRepository();
      addTearDown(repository.dispose);

      await pumpApp(tester, authRepository: repository);
      expect(find.byType(LoginPage), findsOneWidget);

      await tester.tap(find.text('Sign in with Google'));
      await tester.pumpAndSettle();

      expect(find.byType(LibraryScreen), findsOneWidget);
    });

    testWidgets('signing out navigates from the library to login', (
      tester,
    ) async {
      final repository = FakeAuthRepository(
        initialUser: const AuthUser(uid: 'u1', email: 'a@b.com'),
      );
      addTearDown(repository.dispose);

      await pumpApp(tester, authRepository: repository);
      expect(find.byType(LibraryScreen), findsOneWidget);

      // Sign out lives in the account sheet behind the avatar.
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(LibraryScreen), findsNothing);
    });
  });
}
