import 'package:flutter/material.dart';

import '../services/device_status.dart';
import '../services/speech_settings.dart';
import '../widgets/notice_bar.dart';
import 'board_screen.dart';
import 'first_then_screen.dart';
import 'speak_symbols_screen.dart';
import 'speech_setup_screen.dart';

/// Start screen: choose which kind of board to use.
class HomeScreen extends StatefulWidget {
  /// [deviceStatus] and [openSettings] are only overridden in tests.
  const HomeScreen({super.key, this.deviceStatus, this.openSettings});

  final DeviceStatus? deviceStatus;
  final Future<SpeechSettingsRepository> Function()? openSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Bumped after the setup closes, so the notice bar re-checks.
  int _noticeGeneration = 0;

  Future<void> _openSpeechSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SpeechSetupScreen(openSettings: widget.openSettings),
      ),
    );
    if (mounted) setState(() => _noticeGeneration++);
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TalkSimple'),
        actions: [
          IconButton(
            onPressed: _openSpeechSetup,
            icon: const Icon(Icons.settings_voice_outlined),
            tooltip: 'Spracherkennung einrichten',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              NoticeBar(
                key: ValueKey(_noticeGeneration),
                deviceStatus: widget.deviceStatus,
                openSettings: widget.openSettings,
                onAction: (notice) {
                  if (notice == Notice.speechNotSetUp) _openSpeechSetup();
                },
              ),
              Expanded(
                child: _BoardTypeCard(
                  label: 'Sprechen → Symbole',
                  icon: Icons.record_voice_over_outlined,
                  onTap: () => _open(
                    SpeakSymbolsScreen(openSettings: widget.openSettings),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _BoardTypeCard(
                  label: 'Zuerst - Dann',
                  icon: Icons.swap_horiz,
                  onTap: () => _open(const FirstThenScreen()),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _BoardTypeCard(
                  label: 'Zwei Auswahl',
                  icon: Icons.looks_two_outlined,
                  onTap: null,
                  subtitle: 'kommt bald',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _BoardTypeCard(
                  label: 'Frei gestaltbares Board',
                  icon: Icons.grid_view,
                  onTap: () => _open(const BoardScreen()),
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

  /// Below this card height, icon and text sit side by side instead of
  /// stacked, so four cards fit on small or landscape screens.
  static const _compactHeight = 150.0;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = enabled
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: foreground,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
    return Material(
      color: enabled
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < _compactHeight;
            return Padding(
              padding: const EdgeInsets.all(12),
              child: compact
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 40, color: foreground),
                        const SizedBox(width: 16),
                        Flexible(child: FittedBox(child: text)),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 56, color: foreground),
                        const SizedBox(height: 12),
                        text,
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}
