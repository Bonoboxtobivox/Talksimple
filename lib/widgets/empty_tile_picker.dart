import 'package:flutter/material.dart';

import '../models/symbol_tile.dart';
import '../services/drive_symbol_source.dart';
import '../services/speech_service.dart';
import '../services/speech_settings.dart';
import '../services/symbol_library.dart';
import '../services/symbol_resolver.dart';
import 'image_source_dialog.dart';

/// Fills an empty board tile: three equally large, equally easy ways in,
/// for whoever's setting the board up (not the AAC user themselves).
///
/// - Hold the big area down and say the word.
/// - Tap "Bild hinzufügen" to add an image directly (Metacom library,
///   camera, or an existing file from Gallery/Drive).
/// - Tap "Wort eingeben" to type instead of speaking.
///
/// A spoken/typed word is matched against the on-device symbol library
/// (case-insensitive), then against the shared Google Drive folder. No
/// match -> asks whether to take a new photo or pick an existing one, and
/// saves it under that word for next time. Large tap targets throughout -
/// built for users with limited fine motor control.
class EmptyTilePicker extends StatefulWidget {
  /// [speechService] and [openSettings] are only overridden in tests.
  const EmptyTilePicker({
    super.key,
    required this.onResolved,
    this.speechService,
    this.openSettings,
    this.catalog,
  });

  final ValueChanged<SymbolTile> onResolved;
  final SpeechService? speechService;
  final Future<SpeechSettingsRepository> Function()? openSettings;
  final SymbolCatalog? catalog;

  @override
  State<EmptyTilePicker> createState() => _EmptyTilePickerState();
}

class _EmptyTilePickerState extends State<EmptyTilePicker> {
  late final SpeechService _speech =
      widget.speechService ?? DeviceSpeechService();

  bool _listening = false;
  bool _busy = false;
  String? _statusMessage;

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_busy) return;
    final store = await (widget.openSettings ?? openSpeechSettings)();
    final settings = await store.load();
    final available = await _speech.start(settings);
    if (!mounted) return;
    if (!available) {
      setState(() => _statusMessage = 'Spracherkennung nicht verfügbar.');
      return;
    }
    setState(() {
      _listening = true;
      _statusMessage = 'Ich höre zu…';
    });
  }

  Future<void> _stopRecordingAndResolve() async {
    if (!_listening) return;
    final recognized = await _speech.stop();
    if (!mounted) return;
    setState(() => _listening = false);

    if (recognized.isEmpty) {
      setState(() => _statusMessage = 'Nichts verstanden — nochmal versuchen.');
      return;
    }
    await _resolveWord(recognized);
  }

  Future<void> _typeWord() async {
    if (_busy) return;
    final controller = TextEditingController();
    final word = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wort eingeben'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'z.B. Trinken'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Suchen'),
          ),
        ],
      ),
    );
    if (word == null || word.trim().isEmpty || !mounted) return;
    await _resolveWord(word.trim());
  }

  Future<void> _resolveWord(String word) async {
    setState(() {
      _busy = true;
      _statusMessage = 'Suche "$word" …';
    });

    var match = await resolveSymbol(
      word,
      onSearchingDrive: () {
        if (mounted) {
          setState(() => _statusMessage = 'Suche in Google Drive …');
        }
      },
    );

    if (match == null && mounted) {
      match = await _captureFallbackPhoto(word, await SymbolLibrary.open());
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusMessage = null;
    });
    if (match != null) widget.onResolved(match);
  }

  Future<void> _photoDirect() async {
    if (_busy) return;
    final picked = await pickImage(context, catalog: widget.catalog);
    if (picked == null || !mounted) return;

    final controller = TextEditingController(text: picked.suggestedLabel);
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Beschriftung'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'z.B. Trinken'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (label == null || label.trim().isEmpty || !mounted) return;

    setState(() => _busy = true);
    final library = await SymbolLibrary.open();
    final tile = await library.import(
      sourcePath: picked.path,
      label: label.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onResolved(tile);
  }

  /// No symbol found automatically: say why if Drive was the problem, then
  /// let the caregiver pick one (Metacom search pre-filled with [word]).
  Future<SymbolTile?> _captureFallbackPhoto(
    String word,
    SymbolLibrary library,
  ) async {
    final problem = DriveSymbolSource.instance.lastProblem;
    setState(
      () => _statusMessage = problem?.message ?? 'Kein Symbol gefunden …',
    );
    final picked = await pickImage(
      context,
      word: word,
      title: 'Kein Symbol für „$word“',
      catalog: widget.catalog,
    );
    if (picked == null) return null;
    return library.import(sourcePath: picked.path, label: word);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: _RecordArea(
            listening: _listening,
            busy: _busy,
            statusMessage: _statusMessage,
            onPressStart: _startRecording,
            onPressEnd: _stopRecordingAndResolve,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          flex: 2,
          child: Row(
            children: [
              Expanded(
                child: _BigActionButton(
                  icon: Icons.add_photo_alternate_outlined,
                  label: 'Bild hinzufügen',
                  onTap: _busy ? null : _photoDirect,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigActionButton(
                  icon: Icons.keyboard_outlined,
                  label: 'Wort eingeben',
                  onTap: _busy ? null : _typeWord,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecordArea extends StatelessWidget {
  const _RecordArea({
    required this.listening,
    required this.busy,
    required this.statusMessage,
    required this.onPressStart,
    required this.onPressEnd,
  });

  final bool listening;
  final bool busy;
  final String? statusMessage;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPressStart: busy ? null : (_) => onPressStart(),
      onLongPressEnd: busy ? null : (_) => onPressEnd(),
      child: SizedBox.expand(
        child: Material(
          color: listening
              ? colorScheme.errorContainer
              : colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(24),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    listening ? Icons.mic : Icons.mic_none_outlined,
                    size: 88,
                    color: listening
                        ? colorScheme.onErrorContainer
                        : colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    statusMessage ??
                        'Gedrückt halten und sagen,\nwas du sehen möchtest',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (busy) ...[
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BigActionButton extends StatelessWidget {
  const _BigActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Material(
      color: enabled
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 40,
                color: enabled
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: enabled
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
