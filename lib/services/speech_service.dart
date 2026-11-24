import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

import 'speech_settings.dart';

/// Push-to-talk speech recognition: [start] when the button goes down,
/// [stop] when it comes up. Abstracted so widget tests can inject a fake.
abstract class SpeechService {
  /// Starts listening. Returns false if recognition is unavailable (no
  /// permission, no recognizer, missing offline language pack).
  Future<bool> start(SpeechSettings settings);

  /// Stops listening and returns what was recognized ('' for nothing).
  Future<String> stop();

  /// Stops without waiting for a result.
  Future<void> cancel();
}

/// [SpeechService] backed by the device's recognizer (Google on Android).
class DeviceSpeechService implements SpeechService {
  final SpeechToText _speech = SpeechToText();
  Completer<String>? _result;
  String _latest = '';

  @override
  Future<bool> start(SpeechSettings settings) async {
    final available = await _speech.initialize(
      onError: (_) => _complete(_latest),
    );
    if (!available) return false;

    _latest = '';
    _result = Completer<String>();
    await _speech.listen(
      onResult: (result) {
        _latest = result.recognizedWords;
        if (result.finalResult) _complete(_latest);
      },
      listenOptions: SpeechListenOptions(
        // Partial results let stop() return what was heard so far even if
        // the recognizer never sends a final result (common when offline).
        partialResults: true,
        onDevice: settings.onDevice,
        localeId: settings.localeId,
      ),
    );
    return true;
  }

  void _complete(String words) {
    final result = _result;
    if (result != null && !result.isCompleted) result.complete(words);
  }

  @override
  Future<String> stop() async {
    await _speech.stop();
    final result = _result;
    if (result == null) return '';
    final words = await result.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => _latest,
    );
    return words.trim();
  }

  @override
  Future<void> cancel() async {
    _complete('');
    await _speech.cancel();
  }
}
