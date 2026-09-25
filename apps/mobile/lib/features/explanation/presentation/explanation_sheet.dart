import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../activity/application/activity_providers.dart';
import '../application/explanation_providers.dart';
import '../domain/explanation.dart';
import '../domain/prerequisite.dart';
import '../domain/selection_type.dart';

/// Unified sheet showing the backend's contextual explanation for a selection.
///
/// The selection is quoted immediately so the reader keeps their bearings
/// while the explanation loads beneath it.
class ExplanationSheet extends ConsumerWidget {
  const ExplanationSheet({required this.args, super.key});

  final ExplanationArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(explanationProvider(args));

    // A successful explanation counts toward today's tasks.
    ref.listen(explanationProvider(args), (previous, next) {
      if (next is AsyncData && previous is! AsyncData) {
        ref.invalidate(activitySummaryProvider);
      }
    });

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'EXPLAIN',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                      letterSpacing: 1.4,
                    ),
                  ),
                  if (state case AsyncData(:final value)) ...[
                    const SizedBox(width: 8),
                    _TypeBadge(type: value.selectionType),
                  ],
                  const Spacer(),
                  IconButton(
                    tooltip: l10n.close,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 12, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SelectionQuote(
                        text: args.selectedText,
                        type: state.value?.selectionType,
                      ),
                      const SizedBox(height: 22),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOutCubic,
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.topLeft,
                          children: [...previous, ?current],
                        ),
                        child: switch (state) {
                          AsyncData(:final value) => _ExplanationBody(
                            key: const ValueKey('explanation'),
                            explanation: value,
                          ),
                          AsyncError() => _ErrorBody(
                            key: const ValueKey('error'),
                            message: l10n.explanationError,
                            onRetry: () =>
                                ref.invalidate(explanationProvider(args)),
                          ),
                          _ => const _LoadingBody(key: ValueKey('loading')),
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The reader's selection: a large serif headword for single words, an
/// italic pull-quote for sentences and passages.
class _SelectionQuote extends StatelessWidget {
  const _SelectionQuote({required this.text, required this.type});

  final String text;
  final SelectionType? type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = text.trim();
    final isWord =
        type == SelectionType.word ||
        (type == null && !trimmed.contains(RegExp(r'\s')));

    if (isWord) {
      return Text(
        trimmed,
        style: TextStyle(
          fontFamily: AppFonts.serif,
          fontSize: 34,
          fontWeight: FontWeight.w600,
          height: 1.15,
          letterSpacing: -0.6,
          color: theme.colorScheme.onSurface,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.tertiary, width: 3),
        ),
      ),
      child: Text(
        '“$trimmed”',
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: AppFonts.serif,
          fontStyle: FontStyle.italic,
          fontSize: 18,
          height: 1.5,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _ExplanationBody extends StatelessWidget {
  const _ExplanationBody({required this.explanation, super.key});

  final Explanation explanation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final meaning = explanation.meaning;
    final example = explanation.example;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (meaning != null && meaning.isNotEmpty) ...[
          _SectionLabel(l10n.explanationMeaning),
          const SizedBox(height: 6),
          Text(
            meaning,
            style: theme.textTheme.titleLarge?.copyWith(height: 1.3),
          ),
          const SizedBox(height: 22),
        ],
        const _SectionLabel('In this context'),
        const SizedBox(height: 6),
        Text(
          explanation.explanation,
          style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.6),
        ),
        if (example != null && example.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionLabel(l10n.explanationExample),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              example,
              style: TextStyle(
                fontFamily: AppFonts.serif,
                fontStyle: FontStyle.italic,
                fontSize: 16,
                height: 1.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
        if (explanation.prerequisites.isNotEmpty) ...[
          const SizedBox(height: 22),
          _PrerequisitesSection(prerequisites: explanation.prerequisites),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Explained using the surrounding text. AI can make mistakes.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final SelectionType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (type) {
      SelectionType.word => 'WORD',
      SelectionType.sentence => 'SENTENCE',
      SelectionType.paragraph => 'PASSAGE',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 10,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _PrerequisitesSection extends StatelessWidget {
  const _PrerequisitesSection({required this.prerequisites});

  final List<Prerequisite> prerequisites;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final count = prerequisites.length;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(),
          collapsedShape: const RoundedRectangleBorder(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          iconColor: theme.colorScheme.onTertiaryContainer,
          collapsedIconColor: theme.colorScheme.onTertiaryContainer,
          leading: Icon(
            Icons.account_tree_outlined,
            color: theme.colorScheme.tertiary,
          ),
          title: Text(
            l10n.prerequisites,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
          subtitle: Text(
            '$count ${count == 1 ? 'idea' : 'ideas'} worth knowing first',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onTertiaryContainer.withValues(
                alpha: 0.75,
              ),
            ),
          ),
          children: [
            for (var i = 0; i < count; i++)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prerequisites[i].name,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            prerequisites[i].reason,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.tertiary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Reading the context…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SkeletonPulse(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 90, height: 10),
              SizedBox(height: 12),
              SkeletonBox(),
              SizedBox(height: 10),
              SkeletonBox(),
              SizedBox(height: 10),
              SkeletonBox(width: 220),
              SizedBox(height: 26),
              SkeletonBox(height: 64, radius: 14),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.retry),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 44)),
          ),
        ],
      ),
    );
  }
}
