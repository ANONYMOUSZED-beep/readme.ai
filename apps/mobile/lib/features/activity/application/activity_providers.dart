import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../data/activity_repository_impl.dart';
import '../domain/activity_repository.dart';
import '../domain/activity_summary.dart';

/// Provides the [ActivityRepository]. Overridden in tests with a fake.
final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return ActivityRepositoryImpl(ref.watch(dioProvider));
});

/// Holds today's activity summary and changes the daily goal.
///
/// Other features invalidate [activitySummaryProvider] after activity that
/// counts (finishing a reading session, bookmarking, explaining).
class ActivityController extends AsyncNotifier<ActivitySummary> {
  @override
  Future<ActivitySummary> build() =>
      ref.read(activityRepositoryProvider).getSummary();

  /// Set the daily goal; the summary updates from the server's response.
  Future<void> setDailyGoal(int minutes) async {
    final summary = await ref
        .read(activityRepositoryProvider)
        .setDailyGoal(minutes);
    state = AsyncData(summary);
  }
}

/// Exposes today's [ActivitySummary] (streak, goal, week, and tasks).
final activitySummaryProvider =
    AsyncNotifierProvider<ActivityController, ActivitySummary>(
      ActivityController.new,
    );
