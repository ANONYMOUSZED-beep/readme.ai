import 'package:freezed_annotation/freezed_annotation.dart';

part 'activity_summary.freezed.dart';

/// Today's tasks, mirroring the backend ids.
enum DailyTaskKind {
  /// Read for the daily goal.
  read,

  /// Explain passages with AI.
  explain,

  /// Bookmark a passage to revisit.
  bookmark;

  /// Parse the backend id, or `null` for a task this client doesn't know.
  static DailyTaskKind? fromApi(String value) => switch (value) {
    'read' => DailyTaskKind.read,
    'explain' => DailyTaskKind.explain,
    'bookmark' => DailyTaskKind.bookmark,
    _ => null,
  };
}

/// Progress on one of today's tasks.
@freezed
abstract class DailyTask with _$DailyTask {
  const factory DailyTask({
    required DailyTaskKind kind,
    required int progress,
    required int target,
    required bool completed,
  }) = _DailyTask;
}

/// Reading on one day of the recent week.
@freezed
abstract class ActivityDay with _$ActivityDay {
  const factory ActivityDay({
    required DateTime date,
    required int readingSeconds,
    required bool goalMet,
  }) = _ActivityDay;
}

/// The reader's streak, daily goal, recent week, and today's tasks.
@freezed
abstract class ActivitySummary with _$ActivitySummary {
  const factory ActivitySummary({
    required DateTime today,
    required int dailyGoalMinutes,
    required int todayReadingSeconds,
    required bool goalMetToday,
    required int currentStreak,
    required int longestStreak,
    required List<ActivityDay> week,
    required List<DailyTask> tasks,
  }) = _ActivitySummary;

  const ActivitySummary._();

  /// Whole minutes read today.
  int get todayMinutes => todayReadingSeconds ~/ 60;

  /// Minutes still needed to meet today's goal (0 once met).
  int get minutesToGoal => goalMetToday
      ? 0
      : (dailyGoalMinutes - todayMinutes).clamp(1, dailyGoalMinutes);

  /// Fraction of today's goal read, from 0 to 1.
  double get goalProgress =>
      (todayReadingSeconds / (dailyGoalMinutes * 60)).clamp(0.0, 1.0);

  /// Number of today's tasks completed.
  int get completedTasks => tasks.where((task) => task.completed).length;
}
