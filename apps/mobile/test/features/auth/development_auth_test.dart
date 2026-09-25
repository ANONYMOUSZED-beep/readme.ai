import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/app.dart';
import 'package:readme_ai/core/config/app_config.dart';
import 'package:readme_ai/core/config/app_environment.dart';
import 'package:readme_ai/features/auth/application/auth_providers.dart';
import 'package:readme_ai/features/auth/data/development_auth_repository.dart';
import 'package:readme_ai/features/auth/presentation/login_page.dart';
import 'package:readme_ai/features/library/application/library_providers.dart';
import 'package:readme_ai/features/library/presentation/library_screen.dart';

import '../../helpers/fake_library_repository.dart';

AppConfig _config({required bool devAuth}) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://localhost:8000',
  devAuth: devAuth,
);

Future<void> _pumpDevApp(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(_config(devAuth: true)),
        libraryRepositoryProvider.overrideWithValue(FakeLibraryRepository()),
      ],
      child: const ReadMeApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('provider selects the development repository when DEV_AUTH is on', () {
    final container = ProviderContainer(
      overrides: [appConfigProvider.overrideWithValue(_config(devAuth: true))],
    );
    addTearDown(container.dispose);

    expect(
      container.read(authRepositoryProvider),
      isA<DevelopmentAuthRepository>(),
    );
  });

  test('development repository auto-authenticates the mock user', () async {
    final repository = DevelopmentAuthRepository();
    addTearDown(repository.dispose);

    final user = await repository.authStateChanges().first;

    expect(user?.email, 'geo.dev@readme.ai');
    expect(user?.displayName, 'Geo (Development)');
    expect(await repository.idToken(), 'development-token');
  });

  testWidgets('dev mode auto-navigates to the library with a dev banner', (
    tester,
  ) async {
    await _pumpDevApp(tester);

    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(Banner), findsOneWidget);
  });

  testWidgets('logout in dev mode returns to the login screen', (tester) async {
    await _pumpDevApp(tester);
    expect(find.byType(LibraryScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
  });
}
