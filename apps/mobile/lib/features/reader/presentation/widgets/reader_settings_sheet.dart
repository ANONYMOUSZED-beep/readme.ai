import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_mode_controller.dart';
import '../../application/reader_settings.dart';
import '../../application/reader_settings_controller.dart';
import '../reader_palette.dart';

/// Bottom sheet for adjusting reader typography and page appearance.
class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final controller = ref.read(readerSettingsProvider.notifier);
    final themeMode = ref.read(themeModeProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    void choosePage(ReaderPageTone? tone) {
      if (tone == null) {
        themeMode.setMode(ThemeMode.dark);
      } else {
        themeMode.setMode(ThemeMode.light);
        controller.setPageTone(tone);
      }
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Themes & settings', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _Stepper(
                    label: 'Font size',
                    value: settings.fontSize.round().toString(),
                    decreaseIcon: const Text(
                      'A',
                      style: TextStyle(
                        fontFamily: AppFonts.serif,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    increaseIcon: const Text(
                      'A',
                      style: TextStyle(
                        fontFamily: AppFonts.serif,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onDecrease: settings.fontSize > ReaderSettings.minFontSize
                        ? controller.decreaseFontSize
                        : null,
                    onIncrease: settings.fontSize < ReaderSettings.maxFontSize
                        ? controller.increaseFontSize
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Stepper(
                    label: 'Line spacing',
                    value: settings.lineHeight.toStringAsFixed(1),
                    decreaseIcon: const Icon(
                      Icons.density_small_rounded,
                      size: 20,
                    ),
                    increaseIcon: const Icon(
                      Icons.density_large_rounded,
                      size: 20,
                    ),
                    onDecrease:
                        settings.lineHeight > ReaderSettings.minLineHeight
                        ? controller.decreaseLineHeight
                        : null,
                    onIncrease:
                        settings.lineHeight < ReaderSettings.maxLineHeight
                        ? controller.increaseLineHeight
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _Label('Page'),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final (tone, name) in const [
                  (ReaderPageTone.paper, 'Paper'),
                  (ReaderPageTone.sepia, 'Sepia'),
                  (ReaderPageTone.white, 'White'),
                ]) ...[
                  Expanded(
                    child: _PageSwatch(
                      name: name,
                      palette: ReaderPalette.resolve(tone, Brightness.light),
                      serif: settings.typeface == ReaderTypeface.serif,
                      selected: !isDark && settings.pageTone == tone,
                      onTap: () => choosePage(tone),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: _PageSwatch(
                    name: 'Night',
                    palette: ReaderPalette.night,
                    serif: settings.typeface == ReaderTypeface.serif,
                    selected: isDark,
                    onTap: () => choosePage(null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _Label('Typeface'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _TypefaceOption(
                    name: 'Literata',
                    caption: 'Classic serif',
                    fontFamily: AppFonts.serif,
                    selected: settings.typeface == ReaderTypeface.serif,
                    onTap: () => controller.setTypeface(ReaderTypeface.serif),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TypefaceOption(
                    name: 'Sans',
                    caption: 'Modern sans',
                    fontFamily: null,
                    selected: settings.typeface == ReaderTypeface.sans,
                    onTap: () => controller.setTypeface(ReaderTypeface.sans),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A pill with − value + controls; tooltips read "Decrease/Increase [label]".
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.decreaseIcon,
    required this.increaseIcon,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final String value;
  final Widget decreaseIcon;
  final Widget increaseIcon;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(label),
        const SizedBox(height: 10),
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Decrease $label',
                onPressed: onDecrease,
                icon: decreaseIcon,
              ),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Increase $label',
                onPressed: onIncrease,
                icon: increaseIcon,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PageSwatch extends StatelessWidget {
  const _PageSwatch({
    required this.name,
    required this.palette,
    required this.serif,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final ReaderPalette palette;
  final bool serif;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.page,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Text(
                'Aa',
                style: TextStyle(
                  fontFamily: serif ? AppFonts.serif : null,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: palette.ink,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypefaceOption extends StatelessWidget {
  const _TypefaceOption({
    required this.name,
    required this.caption,
    required this.fontFamily,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String caption;
  final String? fontFamily;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.onSurface
              : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Text(
                'Aa',
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleSmall),
                    Text(
                      caption,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
