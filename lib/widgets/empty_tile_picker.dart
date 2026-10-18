import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/symbol_tile.dart';
import '../services/drive_symbol_source.dart';
import '../services/symbol_library.dart';

/// Fills an empty board tile: three equally large, equally easy ways in,
/// for whoever's setting the board up (not the AAC user themselves).
///
/// - Hold the big area down and say the word.
/// - Tap "Bild hinzufügen" to add an image directly (camera or an existing
///   file from Gallery/Drive).
/// - Tap "Wort eingeben" to type instead of speaking.
///
/// A spoken/typed word is matched against the on-device symbol library
/// (case-insensitive), then against the shared Google Drive folder. No
/// match -> asks whether to take a new photo or pick an existing one, and
/// saves it under that word for next time. Large tap targets throughout -
/// built for users with limited fine motor control.
class EmptyTilePicker extends StatefulWidget {
  const EmptyTilePicker({super.key, required this.onResolved});

  final ValueChanged<SymbolTile> onResolved;

  @override
  State<EmptyTilePicker> createState() => _EmptyTilePickerState();
}

class _EmptyTilePickerState extends State<EmptyTilePicker> {
  final SpeechToText _speech = SpeechToText();

  bool _listening = false;
  bool _busy = false;
  String? _statusMessage;
  Completer<String>? _resultCompleter;

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_busy) return;
    final available = await _speech.initialize(
      onError: (error) {
        setState(() {
          _listening = false;
          _statusMessage = 'Spracherkennung nicht verfügbar.';
        });
      },
    );
    if (!available) {
      setState(() => _statusMessage = 'Spracherkennung nicht verfügbar.');
      return;
    }
    setState(() {
      _listening = true;
      _statusMessage = 'Ich höre zu…';
    });
    _resultCompleter = Completer<String>();
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult && !(_resultCompleter?.isCompleted ?? true)) {
          _resultCompleter?.complete(result.recognizedWords);
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: 'de_DE',
        partialResults: false,
      ),
    );
  }

  Future<void> _stopRecordingAndResolve() async {
    if (!_listening) return;
    await _speech.stop();
    final recognized = (await _resultCompleter?.future.timeout(
              const Duration(seconds: 3),
              onTimeout: () => '',
            ) ??
            '')
        .trim();
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

    final library = await SymbolLibrary.open();
    final entries = await library.loadAll();
    SymbolTile? match;
    for (final entry in entries) {
      if (entry.label.toLowerCase() == word.toLowerCase()) {
        match = entry;
        break;
      }
    }

    if (match == null && mounted) {
      setState(() => _statusMessage = 'Suche in Google Drive …');
      final driveFile = await DriveSymbolSource.instance.findAndDownload(word);
      if (driveFile != null) {
        match = await library.import(sourcePath: driveFile.path, label: word);
      }
    }

    match ??= await _captureFallbackPhoto(word, library);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusMessage = null;
    });
    if (match != null) widget.onResolved(match);
  }

  Future<void> _photoDirect() async {
    if (_busy) return;
    final path = await _pickImagePath();
    if (path == null || !mounted) return;

    final controller = TextEditingController();
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
    final tile = await library.import(sourcePath: path, label: label.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onResolved(tile);
  }

  Future<SymbolTile?> _captureFallbackPhoto(
    String label,
    SymbolLibrary library,
  ) async {
    setState(() => _statusMessage = 'Kein Symbol gefunden …');
    final path = await _pickImagePath();
    if (path == null) return null;
    return library.import(sourcePath: path, label: label);
  }

  /// Asks whether to take a new photo or pick an existing image
  /// (Galerie/Drive), then launches the corresponding picker. Returns the
  /// resulting file path, or null if either dialog was cancelled.
  Future<String?> _pickImagePath() async {
    final useCamera = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bild hinzufügen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.maxFinite,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Kamera'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.maxFinite,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Galerie / Drive'),
              ),
            ),
          ],
        ),
      ),
    );
    if (useCamera == null || !mounted) return null;

    if (useCamera) {
      final photo = await ImagePicker().pickImage(source: ImageSource.camera);
      return photo?.path;
    }
    // FileType.image would launch Android's restricted Photo Picker, which
    // excludes cloud providers like Google Drive. FileType.custom launches
    // the full system document picker instead, which lists Drive as a
    // source alongside local storage.
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'],
    );
    return result?.files.single.path;
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
