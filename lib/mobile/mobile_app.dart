import 'package:flutter/material.dart';

import '../shared/theme.dart';

/// YesEm Mobile. Intentionally a single placeholder page for now.
class MobileApp extends StatelessWidget {
  const MobileApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'YesEm Mobile',
    theme: yesemTheme(),
    home: const MobileHomePage(),
  );
}

class MobileHomePage extends StatelessWidget {
  const MobileHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.badge_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text('YesEm Mobile', style: textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Mobile application placeholder',
                  style: textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
