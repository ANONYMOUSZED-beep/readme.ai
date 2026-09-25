import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/activity_summary.dart';

/// The streak accent for the current brightness.
Color flameColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppColors.flameDark
    : AppColors.flame;

/// Title shown for a daily task.
String dailyTaskTitle(DailyTask task) => switch (task.kind) {
  DailyTaskKind.read => 'Read for ${task.target} minutes',
  DailyTaskKind.explain =>
    task.target == 1
        ? 'Explain a passage with AI'
        : 'Explain ${task.target} passages with AI',
  DailyTaskKind.bookmark => 'Bookmark a passage to revisit',
};

/// Compact progress label for a daily task, e.g. `4/10 min`.
String dailyTaskProgress(DailyTask task) => task.kind == DailyTaskKind.read
    ? '${task.progress}/${task.target} min'
    : '${task.progress}/${task.target}';

/// A flame in a soft circle; grey until a streak exists.
class FlameBadge extends StatelessWidget {
  const FlameBadge({required this.lit, this.size = 44, super.key});

  final bool lit;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flame = flameColor(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: lit
            ? flame.withValues(alpha: 0.14)
            : theme.colorScheme.surfaceContainerHigh,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.local_fire_department_rounded,
        size: size * 0.55,
        color: lit ? flame : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A ring showing progress toward today's goal, with minutes in the middle.
class GoalRing extends StatelessWidget {
  const GoalRing({required this.summary, this.size = 56, super.key});

  final ActivitySummary summary;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flame = flameColor(context);
    return Semantics(
      label:
          '${summary.todayMinutes} of ${summary.dailyGoalMinutes} minutes '
          'read today',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            progress: summary.goalProgress,
            color: flame,
            track: theme.colorScheme.surfaceContainerHigh,
            stroke: size * 0.09,
          ),
          child: Center(
            child: summary.goalMetToday
                ? Icon(Icons.check_rounded, color: flame, size: size * 0.42)
                : ExcludeSemantics(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${summary.todayMinutes}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          '/${summary.dailyGoalMinutes}m',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 9,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}

/// The last seven days: a flame check for goal days, today's partial ring.
class WeekStrip extends StatelessWidget {
  const WeekStrip({required this.summary, this.showMinutes = false, super.key});

  final ActivitySummary summary;

  /// Also show minutes read under each day.
  final bool showMinutes;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flame = flameColor(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final day in summary.week)
          _DayDot(
            letter: _letters[day.date.weekday - 1],
            day: day,
            isToday: _sameDay(day.date, summary.today),
            todayProgress: summary.goalProgress,
            flame: flame,
            theme: theme,
            showMinutes: showMinutes,
          ),
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.letter,
    required this.day,
    required this.isToday,
    required this.todayProgress,
    required this.flame,
    required this.theme,
    required this.showMinutes,
  });

  final String letter;
  final ActivityDay day;
  final bool isToday;
  final double todayProgress;
  final Color flame;
  final ThemeData theme;
  final bool showMinutes;

  @override
  Widget build(BuildContext context) {
    const size = 30.0;
    final Widget dot;
    if (day.goalMet) {
      dot = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: flame, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 17, color: Colors.white),
      );
    } else if (isToday) {
      dot = SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            progress: todayProgress,
            color: flame,
            track: theme.colorScheme.outlineVariant,
            stroke: 2.5,
          ),
        ),
      );
    } else {
      dot = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: day.readingSeconds > 0
              ? theme.colorScheme.surfaceContainerHigh
              : null,
          shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
      );
    }
    final minutes = day.readingSeconds ~/ 60;
    return Semantics(
      label:
          '$letter: ${day.goalMet ? 'goal met' : '$minutes minutes read'}'
          '${isToday ? ', today' : ''}',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Text(
              letter,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isToday
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            dot,
            if (showMinutes) ...[
              const SizedBox(height: 4),
              Text(
                minutes == 0 ? '–' : '${minutes}m',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
