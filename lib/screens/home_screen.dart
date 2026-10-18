import 'package:flutter/material.dart';

import 'board_screen.dart';
import 'first_then_screen.dart';

/// Start screen: choose which kind of board to use.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TalkSimple')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: _BoardTypeCard(
                  label: 'Zuerst - Dann',
                  icon: Icons.swap_horiz,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FirstThenScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _BoardTypeCard(
                  label: 'Zwei Auswahl',
                  icon: Icons.looks_two_outlined,
                  onTap: null,
                  subtitle: 'kommt bald',
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _BoardTypeCard(
                  label: 'Frei gestaltbares Board',
                  icon: Icons.grid_view,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BoardScreen()),
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

class _BoardTypeCard extends StatelessWidget {
  const _BoardTypeCard({
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: enabled
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 56,
                color: enabled
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: enabled
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
