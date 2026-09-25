import 'package:dio/dio.dart';

import '../domain/activity_repository.dart';
import '../domain/activity_summary.dart';

/// [ActivityRepository] backed by the ReadMe.ai HTTP API via [Dio].
///
/// The device's UTC offset is attached by the shared `TimezoneInterceptor`,
/// so "today" is the reader's local day.
class ActivityRepositoryImpl implements ActivityRepository {
  const ActivityRepositoryImpl(this._dio);

  static const _base = '/api/v1/activity';

  final Dio _dio;

  @override
  Future<ActivitySummary> getSummary() async {
    final response = await _dio.get<Map<String, dynamic>>('$_base/summary');
    return activitySummaryFromJson(response.data!);
  }

  @override
  Future<ActivitySummary> setDailyGoal(int minutes) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '$_base/goal',
      data: {'daily_minutes': minutes},
    );
    return activitySummaryFromJson(response.data!);
  }
}

/// Decode the backend's activity summary JSON.
ActivitySummary activitySummaryFromJson(Map<String, dynamic> json) {
  final week = (json['week'] as List<dynamic>).cast<Map<String, dynamic>>();
  final tasks = (json['tasks'] as List<dynamic>).cast<Map<String, dynamic>>();
  return ActivitySummary(
    today: DateTime.parse(json['today'] as String),
    dailyGoalMinutes: json['daily_goal_minutes'] as int,
    todayReadingSeconds: json['today_reading_seconds'] as int,
    goalMetToday: json['goal_met_today'] as bool,
    currentStreak: json['current_streak'] as int,
    longestStreak: json['longest_streak'] as int,
    week: [
      for (final day in week)
        ActivityDay(
          date: DateTime.parse(day['date'] as String),
          readingSeconds: day['reading_seconds'] as int,
          goalMet: day['goal_met'] as bool,
        ),
    ],
    tasks: [
      for (final task in tasks)
        if (DailyTaskKind.fromApi(task['id'] as String) case final kind?)
          DailyTask(
            kind: kind,
            progress: task['progress'] as int,
            target: task['target'] as int,
            completed: task['completed'] as bool,
          ),
    ],
  );
}
