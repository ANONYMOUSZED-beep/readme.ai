import 'package:readme_ai/features/activity/domain/activity_repository.dart';
import 'package:readme_ai/features/activity/domain/activity_summary.dart';

/// In-memory [ActivityRepository] for widget tests.
class FakeActivityRepository implements ActivityRepository {
  FakeActivityRepository({ActivitySummary? summary})
    : summary = summary ?? sample();

  ActivitySummary summary;

  /// Goals requested through [setDailyGoal], in order.
  final List<int> goalChanges = [];

  int summaryCalls = 0;

  /// A reader on a 4-day streak, 6 of 10 minutes into today.
  static ActivitySummary sample({
    int streak = 4,
    int todaySeconds = 6 * 60,
    int goalMinutes = 10,
  }) {
    final today = DateTime(2026, 9, 25);
    final met = todaySeconds >= goalMinutes * 60;
    return ActivitySummary(
      today: today,
      dailyGoalMinutes: goalMinutes,
      todayReadingSeconds: todaySeconds,
      goalMetToday: met,
      currentStreak: streak,
      longestStreak: 9,
      week: [
        for (var i = 6; i >= 0; i--)
          ActivityDay(
            date: today.subtract(Duration(days: i)),
            readingSeconds: i == 0 ? todaySeconds : (i <= streak ? 900 : 0),
            goalMet: i == 0 ? met : i <= streak,
          ),
      ],
      tasks: [
        DailyTask(
          kind: DailyTaskKind.read,
          progress: (todaySeconds ~/ 60).clamp(0, goalMinutes),
          target: goalMinutes,
          completed: met,
        ),
        const DailyTask(
          kind: DailyTaskKind.explain,
          progress: 3,
          target: 3,
          completed: true,
        ),
        const DailyTask(
          kind: DailyTaskKind.bookmark,
          progress: 0,
          target: 1,
          completed: false,
        ),
      ],
    );
  }

  @override
  Future<ActivitySummary> getSummary() async {
    summaryCalls++;
    return summary;
  }

  @override
  Future<ActivitySummary> setDailyGoal(int minutes) async {
    goalChanges.add(minutes);
    summary = sample(
      streak: summary.currentStreak,
      todaySeconds: summary.todayReadingSeconds,
      goalMinutes: minutes,
    );
    return summary;
  }
}
