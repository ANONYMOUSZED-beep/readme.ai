import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/activity/data/activity_repository_impl.dart';
import 'package:readme_ai/features/activity/domain/activity_summary.dart';
import 'package:readme_ai/features/activity/presentation/streak_sheet.dart';
import 'package:readme_ai/features/auth/domain/auth_user.dart';
import 'package:readme_ai/features/library/domain/book.dart';
import 'package:readme_ai/features/library/domain/book_status.dart';

import '../../helpers/fake_activity_repository.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_library_repository.dart';
import '../../helpers/pump_app.dart';

const _signedIn = AuthUser(uid: 'u1', email: 'a@b.com');

final _book = Book(
  id: 'b1',
  title: 'Clean Architecture',
  originalFilename: 'Clean Architecture.txt',
  mimeType: 'text/plain',
  fileSize: 2048,
  status: BookStatus.ready,
  uploadedAt: DateTime(2026),
);

Future<FakeActivityRepository> _pumpHome(
  WidgetTester tester, {
  FakeActivityRepository? activity,
}) async {
  final auth = FakeAuthRepository(initialUser: _signedIn);
  addTearDown(auth.dispose);
  final repository = activity ?? FakeActivityRepository();
  await pumpApp(
    tester,
    authRepository: auth,
    libraryRepository: FakeLibraryRepository(initial: [_book]),
    activityRepository: repository,
  );
  return repository;
}

void main() {
  testWidgets('home shows the streak, goal progress, and daily tasks', (
    tester,
  ) async {
    await _pumpHome(tester);

    expect(find.textContaining('day streak'), findsOneWidget);
    expect(find.text('Read 4 more minutes today to keep it going'), findsOne);
    expect(find.text("Today's tasks"), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('Read for 10 minutes'), findsOneWidget);
    expect(find.text('6/10 min'), findsOneWidget);
    expect(find.text('Explain 3 passages with AI'), findsOneWidget);
    expect(find.text('Bookmark a passage to revisit'), findsOneWidget);
  });

  testWidgets('a reader without a streak is invited to start one', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      activity: FakeActivityRepository(
        summary: FakeActivityRepository.sample(streak: 0, todaySeconds: 0),
      ),
    );

    expect(find.text('Start a streak'), findsOneWidget);
    expect(find.text('Read 10 more minutes today to begin'), findsOneWidget);
  });

  testWidgets('the streak sheet changes the daily goal', (tester) async {
    final activity = await _pumpHome(tester);

    await tester.tap(find.textContaining('day streak'));
    await tester.pumpAndSettle();

    expect(find.byType(StreakSheet), findsOneWidget);
    expect(find.textContaining('4-day'), findsOneWidget);

    await tester.ensureVisible(find.text('20 min'));
    await tester.tap(find.text('20 min'));
    await tester.pumpAndSettle();

    expect(activity.goalChanges, [20]);
    // The home card behind the sheet now targets the new goal.
    expect(find.text('Read for 20 minutes'), findsOneWidget);
  });

  test('parses the summary and skips tasks this client does not know', () {
    final summary = activitySummaryFromJson({
      'today': '2026-09-25',
      'daily_goal_minutes': 15,
      'today_reading_seconds': 300,
      'goal_met_today': false,
      'current_streak': 2,
      'longest_streak': 5,
      'week': [
        {'date': '2026-09-25', 'reading_seconds': 300, 'goal_met': false},
      ],
      'tasks': [
        {'id': 'read', 'progress': 5, 'target': 15, 'completed': false},
        {'id': 'future-task', 'progress': 0, 'target': 1, 'completed': false},
      ],
    });

    expect(summary.dailyGoalMinutes, 15);
    expect(summary.minutesToGoal, 10);
    expect(summary.goalProgress, closeTo(1 / 3, 0.001));
    expect(summary.tasks.single.kind, DailyTaskKind.read);
    expect(summary.week.single.date, DateTime(2026, 9, 25));
  });
}
