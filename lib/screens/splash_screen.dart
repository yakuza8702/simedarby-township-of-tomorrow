/// Branded boot splash — replaces the bare spinner while [bootShared] runs.
/// Holds the recycling mark, wordmark and tagline. When
/// `MediaQuery.disableAnimations` is true (reduce-motion, tests) it renders
/// no spinner and no indeterminate motion at all.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const String wordmark = 'Township of Tomorrow';
  static const String tagline = 'Point, sort, prove — all on device';

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: context.tTintGreen,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.recycling, size: 88, color: context.tBrand),
            const SizedBox(height: 20),
            Text(
              wordmark,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: context.tInk,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              tagline,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.tMuted, fontSize: 15, height: 1.3),
            ),
            if (!reducedMotion) ...[
              const SizedBox(height: 28),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: context.tBrand),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
