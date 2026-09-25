import 'activity_summary.dart';

/// Contract for the reader's daily activity: streak, goal, and tasks.
///
/// The Dio-backed implementation is injected via Riverpod so a fake can be
/// used in tests.
abstract interface class ActivityRepository {
  /// Fetch today's summary (today is the device's local day).
  Future<ActivitySummary> getSummary();

  /// Change the daily reading goal and return the updated summary.
  Future<ActivitySummary> setDailyGoal(int minutes);
}
