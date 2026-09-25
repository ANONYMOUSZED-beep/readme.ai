import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/app.dart';
import 'package:readme_ai/core/files/file_picker_service.dart';
import 'package:readme_ai/features/activity/application/activity_providers.dart';
import 'package:readme_ai/features/activity/domain/activity_repository.dart';
import 'package:readme_ai/features/auth/application/auth_providers.dart';
import 'package:readme_ai/features/auth/domain/auth_repository.dart';
import 'package:readme_ai/features/library/application/library_providers.dart';
import 'package:readme_ai/features/library/domain/library_repository.dart';
import 'package:readme_ai/features/reader/application/reader_providers.dart';
import 'package:readme_ai/features/reader/domain/reader_repository.dart';

import 'fake_activity_repository.dart';
import 'fake_file_picker.dart';
import 'fake_library_repository.dart';
import 'fake_reader_repository.dart';

/// Pump the full app with fakes injected for all external dependencies, so no
/// platform services (Firebase, HTTP, native file picker) are touched.
///
/// Pass [settle] = false when a fake is intentionally left pending (e.g. to
/// assert a loading state), since `pumpAndSettle` would otherwise hang.
Future<void> pumpApp(
  WidgetTester tester, {
  required AuthRepository authRepository,
  LibraryRepository? libraryRepository,
  FilePickerService? filePicker,
  ReaderRepository? readerRepository,
  ActivityRepository? activityRepository,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        libraryRepositoryProvider.overrideWithValue(
          libraryRepository ?? FakeLibraryRepository(),
        ),
        filePickerProvider.overrideWithValue(filePicker ?? FakeFilePicker()),
        readerRepositoryProvider.overrideWithValue(
          readerRepository ?? FakeReaderRepository(),
        ),
        activityRepositoryProvider.overrideWithValue(
          activityRepository ?? FakeActivityRepository(),
        ),
      ],
      child: const ReadMeApp(),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
}
