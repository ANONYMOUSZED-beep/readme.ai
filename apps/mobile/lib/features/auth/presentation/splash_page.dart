import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Branded transition shown while the persisted session is resolved.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Center(
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          tween: Tween(begin: 0, end: 1),
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.scale(scale: 0.94 + 0.06 * value, child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  size: 32,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'ReadMe.ai',
                style: TextStyle(
                  fontFamily: AppFonts.serif,
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.6,
                  color: AppColors.paper,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 64,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: AppColors.insightDark,
                    backgroundColor: AppColors.paper.withValues(alpha: 0.12),
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
