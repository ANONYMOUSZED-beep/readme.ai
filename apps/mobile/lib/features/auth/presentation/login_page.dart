import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/auth_controller.dart';
import '../domain/auth_exception.dart';

/// Responsive sign-in experience for ReadMe.ai.
class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(authControllerProvider);

    ref.listen(authControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        _showError(context, l10n, error);
      }
    });

    final signIn = _SignInActions(
      isLoading: state.isLoading,
      onPressed: state.isLoading
          ? null
          : () => ref.read(authControllerProvider.notifier).signInWithGoogle(),
    );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 860
              ? _WideLayout(signIn: signIn, height: constraints.maxHeight)
              : _CompactLayout(signIn: signIn, height: constraints.maxHeight),
        ),
      ),
    );
  }

  void _showError(BuildContext context, AppLocalizations l10n, Object error) {
    if (error is AuthException && error.isCancellation) return;
    final message = error is AuthException
        ? error.displayMessage
        : l10n.signInError;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Phones: the story scrolls above sign-in actions pinned to the bottom, so
/// the call to action is always visible without scrolling.
class _CompactLayout extends StatelessWidget {
  const _CompactLayout({required this.signIn, required this.height});

  final Widget signIn;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Shrink the preview on short screens rather than pushing content away.
    final previewScale = ((height - 440) / _ProductPreview.height).clamp(
      0.5,
      1.0,
    );
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Column(
              children: [
                const _BrandMark(),
                SizedBox(height: 28 * previewScale),
                SizedBox(
                  height: _ProductPreview.height * previewScale,
                  child: const FittedBox(child: _ProductPreview()),
                ),
                SizedBox(height: 32 * previewScale),
                const _Headline(compact: true),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: signIn,
        ),
      ],
    );
  }
}

/// Tablets and desktop: copy and actions beside the product preview.
class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.signIn, required this.height});

  final Widget signIn;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height - 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _BrandMark(),
                      const SizedBox(height: 56),
                      const _Headline(),
                      const SizedBox(height: 40),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: signIn,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 64),
                const Expanded(child: Center(child: _ProductPreview())),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and lifts [child] into place on first build.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    final total = 700 + delayMs;
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: total),
      curve: Interval(delayMs / total, 1, curve: Curves.easeOutCubic),
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final align = compact ? TextAlign.center : TextAlign.left;
    return _Entrance(
      delayMs: 120,
      child: Column(
        crossAxisAlignment: compact
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Text(
            'Read less.\nUnderstand more.',
            textAlign: align,
            style: compact
                ? theme.textTheme.displaySmall
                : theme.textTheme.displayLarge,
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              '${l10n.loginSubtitle} Select any word or passage and get a '
              'clear explanation, right where you are reading.',
              textAlign: align,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 17,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInActions extends StatelessWidget {
  const _SignInActions({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return _Entrance(
      delayMs: 240,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          children: [
            FilledButton.icon(
              onPressed: onPressed,
              icon: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : const _GoogleGlyph(),
              label: Text(l10n.signInWithGoogle),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Private by design. Your library stays yours.',
                    style: theme.textTheme.bodySmall,
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

/// A miniature reader page demonstrating the core interaction: a highlighted
/// word with its in-context explanation.
class _ProductPreview extends StatelessWidget {
  const _ProductPreview();

  static const double width = 340;
  static const double height = 318;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ink = theme.colorScheme.onSurface;
    final body = TextStyle(
      fontFamily: AppFonts.serif,
      fontSize: 15,
      height: 1.65,
      color: ink.withValues(alpha: 0.82),
    );

    return _Entrance(
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The page.
            Positioned(
              left: 14,
              right: 14,
              top: 0,
              child: Transform.rotate(
                angle: -1.5 * math.pi / 180,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 34),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.nightRaised
                        : AppColors.paperRaised,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.ink.withValues(alpha: 0.10),
                        blurRadius: 40,
                        offset: const Offset(0, 22),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CHAPTER ONE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text.rich(
                        TextSpan(
                          style: body,
                          children: [
                            const TextSpan(
                              text:
                                  'The summer felt endless, yet every '
                                  'golden afternoon was ',
                            ),
                            TextSpan(
                              text: 'ephemeral',
                              style: body.copyWith(
                                color: ink,
                                backgroundColor: theme.colorScheme.tertiary
                                    .withValues(alpha: 0.22),
                              ),
                            ),
                            const TextSpan(
                              text:
                                  ' — here, and then gone before '
                                  'anyone thought to hold on.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // The explanation card.
            Positioned(
              left: 0,
              right: 40,
              bottom: 0,
              child: _Entrance(
                delayMs: 420,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.ink.withValues(alpha: 0.22),
                        blurRadius: 30,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 15,
                            color: isDark
                                ? AppColors.insight
                                : AppColors.insightDark,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'EPHEMERAL',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimary.withValues(
                                alpha: 0.7,
                              ),
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Lasting a very short time. Here, the author '
                        'contrasts how long summer feels with how quickly '
                        'each moment passes.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            Icons.auto_stories_rounded,
            size: 19,
            color: theme.colorScheme.onPrimary,
          ),
        ),
        const SizedBox(width: 10),
        Text('ReadMe.ai', style: theme.textTheme.titleLarge),
      ],
    );
  }
}

/// The four-color Google "G", drawn so no image asset is required.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.22;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    double rad(double degrees) => degrees * math.pi / 180;

    canvas
      ..drawArc(rect, rad(-40), rad(-100), false, arc(const Color(0xFFEA4335)))
      ..drawArc(rect, rad(-140), rad(-90), false, arc(const Color(0xFFFBBC05)))
      ..drawArc(rect, rad(-230), rad(-95), false, arc(const Color(0xFF34A853)))
      ..drawArc(rect, rad(-325), rad(-35), false, arc(const Color(0xFF4285F4)))
      ..drawRect(
        Rect.fromLTWH(
          size.width / 2,
          size.height / 2 - stroke / 2,
          size.width / 2 - stroke * 0.1,
          stroke,
        ),
        Paint()..color = const Color(0xFF4285F4),
      );
  }

  @override
  bool shouldRepaint(_GooglePainter oldDelegate) => false;
}
