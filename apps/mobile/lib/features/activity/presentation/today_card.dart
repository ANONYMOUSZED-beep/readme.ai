import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/skeleton.dart';
import '../application/activity_providers.dart';
import '../domain/activity_summary.dart';
import 'streak_sheet.dart';
import 'widgets/activity_visuals.dart';

/// Home card for today: streak, goal ring, the recent week, and daily tasks.
///
/// Hidden if the summary can't be loaded — it's encouragement, not content
/// the library depends on.
class TodayCard extends ConsumerWidget {
  const TodayCard({this.onRead, super.key});

  /// Invoked from the reading task (e.g. to continue the last book).
  final VoidCallback? onRead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activitySummaryProvider);
    if (state.value case final summary?) {
      return _TodayCardBody(summary: summary, onRead: onRead);
    }
    if (state.hasError) return const SizedBox.shrink();
    return const _TodayCardSkeleton();
  }
}

class _TodayCardBody extends StatelessWidget {
  const _TodayCardBody({required this.summary, required this.onRead});

  final ActivitySummary summary;
  final VoidCallback? onRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final streak = summary.currentStreak;
    final allDone = summary.completedTasks == summary.tasks.length;

    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => showStreakSheet(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      FlameBadge(lit: streak > 0),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: streak > 0
                                    ? [
                                        TextSpan(
                                          text: '$streak',
                                          style: TextStyle(
                                            fontFamily: AppFonts.serif,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w600,
                                            color: theme.colorScheme.onSurface,
                                            height: 1.1,
                                          ),
                                        ),
                                        TextSpan(
                                          text: '  day streak',
                                          style: theme.textTheme.titleSmall,
                                        ),
                                      ]
                                    : [
                                        TextSpan(
                                          text: 'Start a streak',
                                          style: theme.textTheme.titleLarge,
                                        ),
                                      ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _statusLine(summary),
                              style: theme.textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      GoalRing(summary: summary),
                    ],
                  ),
                  const SizedBox(height: 16),
                  WeekStrip(summary: summary),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Today's tasks",
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  allDone
                      ? 'All done'
                      : '${summary.completedTasks} of ${summary.tasks.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: allDone
                        ? flameColor(context)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          for (final task in summary.tasks)
            _TaskRow(
              task: task,
              onTap: task.kind == DailyTaskKind.read && !task.completed
                  ? onRead
                  : null,
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

String _statusLine(ActivitySummary summary) {
  if (summary.goalMetToday) {
    return "Today's goal is done — nice reading.";
  }
  final remaining = summary.minutesToGoal;
  final minutes = remaining == 1 ? '1 more minute' : '$remaining more minutes';
  return summary.currentStreak > 0
      ? 'Read $minutes today to keep it going'
      : 'Read $minutes today to begin';
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, this.onTap});

  final DailyTask task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = task.completed;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: done ? theme.colorScheme.primary : null,
                shape: BoxShape.circle,
                border: done
                    ? null
                    : Border.all(color: theme.colorScheme.outline, width: 1.5),
              ),
              child: done
                  ? Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: theme.colorScheme.onPrimary,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                dailyTaskTitle(task),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: done
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              dailyTaskProgress(task),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TodayCardSkeleton extends StatelessWidget {
  const _TodayCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonPulse(child: SkeletonBox(height: 250, radius: 22));
  }
}
