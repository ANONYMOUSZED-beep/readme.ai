import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../application/activity_providers.dart';
import '../domain/activity_summary.dart';
import 'widgets/activity_visuals.dart';

/// Daily goals the reader can pick, in minutes.
const readingGoalOptions = [5, 10, 15, 20, 30, 45, 60];

/// Open the streak sheet: streak story, stats, week, and the goal picker.
Future<void> showStreakSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const StreakSheet(),
  );
}

/// The reader's streak in depth, and where the daily goal is set.
class StreakSheet extends ConsumerWidget {
  const StreakSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(activitySummaryProvider).value;
    if (summary == null) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final theme = Theme.of(context);
    final flame = flameColor(context);
    final streak = summary.currentStreak;
    final headline = theme.textTheme.displaySmall;
    final accent = headline?.copyWith(
      color: flame,
      fontStyle: FontStyle.italic,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.local_fire_department_rounded, size: 44, color: flame),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                style: headline,
                children: streak > 0
                    ? [
                        const TextSpan(text: "You're on a\n"),
                        TextSpan(text: '$streak-day', style: accent),
                        const TextSpan(text: ' streak'),
                      ]
                    : [
                        const TextSpan(text: 'Start a\n'),
                        TextSpan(text: 'reading', style: accent),
                        const TextSpan(text: ' streak'),
                      ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _story(summary),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _Stat(label: 'Current', value: _days(streak)),
                const SizedBox(width: 10),
                _Stat(label: 'Longest', value: _days(summary.longestStreak)),
                const SizedBox(width: 10),
                _Stat(label: 'Today', value: '${summary.todayMinutes} min'),
              ],
            ),
            const SizedBox(height: 24),
            Text('This week', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            WeekStrip(summary: summary, showMinutes: true),
            const SizedBox(height: 28),
            Text('Daily goal', style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              'Reading time that counts toward your streak. Changes apply '
              'from today.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _GoalPicker(selected: summary.dailyGoalMinutes),
          ],
        ),
      ),
    );
  }
}

String _days(int count) => count == 1 ? '1 day' : '$count days';

String _story(ActivitySummary summary) {
  final goal = summary.dailyGoalMinutes;
  if (summary.goalMetToday) {
    return "Today's $goal minutes are done. Come back tomorrow to keep it "
        'growing.';
  }
  if (summary.currentStreak > 0) {
    return 'Read ${summary.minutesToGoal} more minutes today to keep it '
        'going.';
  }
  return 'Read $goal minutes a day to build the habit — a little every day '
      'adds up fast.';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontFamily: AppFonts.serif,
                fontSize: 19,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _GoalPicker extends ConsumerStatefulWidget {
  const _GoalPicker({required this.selected});

  final int selected;

  @override
  ConsumerState<_GoalPicker> createState() => _GoalPickerState();
}

class _GoalPickerState extends ConsumerState<_GoalPicker> {
  int? _saving;

  Future<void> _choose(int minutes) async {
    if (minutes == widget.selected || _saving != null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = minutes);
    try {
      await ref.read(activitySummaryProvider.notifier).setDailyGoal(minutes);
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't update your goal. Try again.")),
      );
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = {...readingGoalOptions, widget.selected}.toList()..sort();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final minutes in options)
          ChoiceChip(
            label: _saving == minutes
                ? SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onSurface,
                    ),
                  )
                : Text('$minutes min'),
            selected: minutes == widget.selected,
            showCheckmark: false,
            selectedColor: theme.colorScheme.primary,
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              color: minutes == widget.selected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
            ),
            onSelected: (_) => _choose(minutes),
          ),
      ],
    );
  }
}
