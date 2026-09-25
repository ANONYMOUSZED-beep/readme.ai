import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/activity/application/activity_providers.dart';
import 'package:readme_ai/features/activity/domain/activity_repository.dart';
import 'package:readme_ai/features/explanation/application/explanation_providers.dart';
import 'package:readme_ai/features/explanation/domain/explanation_repository.dart';
import 'package:readme_ai/features/reader/application/reader_providers.dart';
import 'package:readme_ai/features/reader/domain/reader_repository.dart';
import 'package:readme_ai/features/reader/presentation/reader_screen.dart';
import 'package:readme_ai/l10n/generated/app_localizations.dart';

import 'fake_activity_repository.dart';

/// Pump the [ReaderScreen] inside a minimal app with fakes for the reader and
/// (optionally) explanation repositories. Returns the container so tests can
/// read providers.
Future<ProviderContainer> pumpReader(
  WidgetTester tester, {
  required ReaderRepository repository,
  ExplanationRepository? explanationRepository,
  ActivityRepository? activityRepository,
  String bookId = 'b1',
}) async {
  final container = ProviderContainer(
    overrides: [
      readerRepositoryProvider.overrideWithValue(repository),
      activityRepositoryProvider.overrideWithValue(
        activityRepository ?? FakeActivityRepository(),
      ),
      if (explanationRepository != null)
        explanationRepositoryProvider.overrideWithValue(explanationRepository),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ReaderScreen(bookId: bookId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}
