import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// One German variant the speech recognizer can listen for.
class SpeechVariant {
  const SpeechVariant(this.localeId, this.label);

  final String localeId;
  final String label;
}

/// The variants offered in the setup. Austrian first: regional
/// pronunciation is recognized noticeably better with the matching locale.
const speechVariants = [
  SpeechVariant('de_AT', 'Deutsch (Österreich)'),
  SpeechVariant('de_DE', 'Deutsch (Deutschland)'),
  SpeechVariant('de_CH', 'Deutsch (Schweiz)'),
];

/// How speech recognition is configured on this device.
class SpeechSettings {
  const SpeechSettings({
    this.localeId = 'de_DE',
    this.onDevice = false,
    this.configured = false,
  });

  /// Locale passed to the recognizer, e.g. `de_AT`.
  final String localeId;

  /// Recognize on the device only (works without internet, needs the
  /// offline language pack). False = Google online recognition.
  final bool onDevice;

  /// Whether the setup was completed once. Until then the app shows a
  /// hint to run it.
  final bool configured;

  String get variantLabel => speechVariants
      .firstWhere(
        (v) => v.localeId == localeId,
        orElse: () => SpeechVariant(localeId, localeId),
      )
      .label;

  SpeechSettings copyWith({
    String? localeId,
    bool? onDevice,
    bool? configured,
  }) {
    return SpeechSettings(
      localeId: localeId ?? this.localeId,
      onDevice: onDevice ?? this.onDevice,
      configured: configured ?? this.configured,
    );
  }

  Map<String, dynamic> toJson() => {
    'localeId': localeId,
    'onDevice': onDevice,
    'configured': configured,
  };

  static SpeechSettings fromJson(Map<String, dynamic> json) => SpeechSettings(
    localeId: json['localeId'] as String? ?? 'de_DE',
    onDevice: json['onDevice'] as bool? ?? false,
    configured: json['configured'] as bool? ?? false,
  );
}

/// Where [SpeechSettings] are persisted. Abstracted so widget tests can
/// use an in-memory fake instead of real device storage.
abstract class SpeechSettingsRepository {
  Future<SpeechSettings> load();

  Future<void> save(SpeechSettings settings);
}

class FileSpeechSettingsStore implements SpeechSettingsRepository {
  FileSpeechSettingsStore._(this._file);

  /// [baseDir] overrides where data is stored; only meant for tests.
  static Future<FileSpeechSettingsStore> open({Directory? baseDir}) async {
    final base = baseDir ?? await getApplicationDocumentsDirectory();
    return FileSpeechSettingsStore._(File('${base.path}/speech_settings.json'));
  }

  final File _file;

  @override
  Future<SpeechSettings> load() async {
    try {
      if (!await _file.exists()) return const SpeechSettings();
      final raw = await _file.readAsString();
      if (raw.trim().isEmpty) return const SpeechSettings();
      return SpeechSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      // A corrupt file must never block speaking: fall back to defaults.
      return const SpeechSettings();
    }
  }

  @override
  Future<void> save(SpeechSettings settings) async {
    await _file.writeAsString(jsonEncode(settings.toJson()));
  }
}

/// Opens the settings store used by the app.
Future<SpeechSettingsRepository> openSpeechSettings() =>
    FileSpeechSettingsStore.open();
