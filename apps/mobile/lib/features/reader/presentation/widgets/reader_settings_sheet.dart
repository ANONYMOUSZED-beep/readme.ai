import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme_mode_controller.dart';
import '../../application/reader_settings.dart';
import '../../application/reader_settings_controller.dart';

/// Bottom sheet for adjusting reader typography and appearance.
class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({super.key});

  static void _setTone(WidgetRef ref, ReaderPageTone tone) {
    ref
        .read(themeModeProvider.notifier)
        .setMode(
          tone == ReaderPageTone.dark ? ThemeMode.dark : ThemeMode.light,
        );
    ref
        .read(readerSettingsProvider.notifier)
        .setSepia(enabled: tone == ReaderPageTone.sepia);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final controller = ref.read(readerSettingsProvider.notifier);
    final theme = Theme.of(context);
    final tone = theme.brightness == Brightness.dark
        ? ReaderPageTone.dark
        : settings.sepia
        ? ReaderPageTone.sepia
        : ReaderPageTone.light;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reading style', style: theme.textTheme.titleLarge),
                      Text(
                        'Make the page feel right for you',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _ControlCard(
              child: Column(
                children: [
                  _ChoiceRow<ReaderPageTone>(
                    icon: Icons.contrast_rounded,
                    label: 'Page',
                    selected: tone,
                    segments: const [
                      ButtonSegment(
                        value: ReaderPageTone.light,
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ReaderPageTone.sepia,
                        label: Text('Sepia'),
                      ),
                      ButtonSegment(
                        value: ReaderPageTone.dark,
                        label: Text('Dark'),
                      ),
                    ],
                    onChanged: (value) => _setTone(ref, value),
                  ),
                  Divider(color: theme.colorScheme.outlineVariant),
                  _ChoiceRow<ReaderFont>(
                    icon: Icons.font_download_outlined,
                    label: 'Font',
                    selected: settings.font,
                    segments: const [
                      ButtonSegment(
                        value: ReaderFont.serif,
                        label: Text(
                          'Serif',
                          style: TextStyle(fontFamily: 'Lora'),
                        ),
                      ),
                      ButtonSegment(
                        value: ReaderFont.sans,
                        label: Text('Sans'),
                      ),
                    ],
                    onChanged: controller.setFont,
                  ),
                  Divider(color: theme.colorScheme.outlineVariant),
                  _StepperRow(
                    icon: Icons.format_size_rounded,
                    label: 'Font size',
                    value: settings.fontSize.round().toString(),
                    onDecrease: settings.fontSize > ReaderSettings.minFontSize
                        ? controller.decreaseFontSize
                        : null,
                    onIncrease: settings.fontSize < ReaderSettings.maxFontSize
                        ? controller.increaseFontSize
                        : null,
                  ),
                  Divider(color: theme.colorScheme.outlineVariant),
                  _StepperRow(
                    icon: Icons.format_line_spacing_rounded,
                    label: 'Line spacing',
                    value: settings.lineHeight.toStringAsFixed(1),
                    onDecrease:
                        settings.lineHeight > ReaderSettings.minLineHeight
                        ? controller.decreaseLineHeight
                        : null,
                    onIncrease:
                        settings.lineHeight < ReaderSettings.maxLineHeight
                        ? controller.increaseLineHeight
                        : null,
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

class _ControlCard extends StatelessWidget {
  const _ControlCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: child,
      ),
    );
  }
}

/// A labelled single-choice segmented control.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.segments,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final T selected;
  final List<ButtonSegment<T>> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 10),
          // Full width below the label, so it fits the narrowest phones.
          SegmentedButton<T>(
            segments: segments,
            selected: {selected},
            showSelectedIcon: false,
            onSelectionChanged: (values) => onChanged(values.first),
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
          IconButton.filledTonal(
            tooltip: 'Decrease $label',
            onPressed: onDecrease,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 42,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge,
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Increase $label',
            onPressed: onIncrease,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}
