import 'package:flutter/material.dart';

import '../services/device_status.dart';
import '../services/speech_settings.dart';

/// Short, dismissible warnings above the main content (battery saver on,
/// no internet, speech not set up). Shows nothing when all is well, so it
/// never distracts during normal use.
class NoticeBar extends StatefulWidget {
  const NoticeBar({
    super.key,
    required this.onAction,
    this.deviceStatus,
    this.openSettings,
  });

  /// Called when the button of a notice (e.g. "Einrichten") is tapped.
  final ValueChanged<Notice> onAction;

  /// Only overridden in tests.
  final DeviceStatus? deviceStatus;
  final Future<SpeechSettingsRepository> Function()? openSettings;

  @override
  State<NoticeBar> createState() => _NoticeBarState();
}

class _NoticeBarState extends State<NoticeBar> {
  List<Notice> _notices = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await (await (widget.openSettings ?? openSpeechSettings)())
        .load();
    final notices = await collectNotices(
      widget.deviceStatus ?? PlatformDeviceStatus(),
      settings,
    );
    if (!mounted) return;
    setState(() => _notices = notices);
  }

  @override
  Widget build(BuildContext context) {
    if (_notices.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final notice in _notices)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade900),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    notice.text,
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (notice.action != null)
                  TextButton(
                    onPressed: () => widget.onAction(notice),
                    child: Text(notice.action!),
                  ),
                IconButton(
                  onPressed: () => setState(
                    () => _notices = [
                      for (final n in _notices)
                        if (n != notice) n,
                    ],
                  ),
                  icon: const Icon(Icons.close),
                  tooltip: 'Hinweis schließen',
                ),
              ],
            ),
          ),
      ],
    );
  }
}
