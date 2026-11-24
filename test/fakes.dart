import 'package:talksimple/services/device_status.dart';
import 'package:talksimple/services/favorites_store.dart';
import 'package:talksimple/services/speech_service.dart';
import 'package:talksimple/services/speech_settings.dart';

/// In-memory [FavoritesRepository].
class FakeFavorites implements FavoritesRepository {
  FakeFavorites([List<String>? sentences]) : sentences = sentences ?? [];

  List<String> sentences;

  @override
  Future<List<String>> load() async => List.of(sentences);

  @override
  Future<void> save(List<String> sentences) async {
    this.sentences = List.of(sentences);
  }
}

/// [DeviceStatus] with fixed answers.
class FakeDeviceStatus implements DeviceStatus {
  FakeDeviceStatus({this.online = true, this.powerSave = false});

  final bool online;
  final bool powerSave;

  @override
  Future<bool> isOnline() async => online;

  @override
  Future<bool> isPowerSaveMode() async => powerSave;
}

/// In-memory [SpeechSettingsRepository].
class FakeSpeechSettings implements SpeechSettingsRepository {
  FakeSpeechSettings([this.settings = const SpeechSettings()]);

  SpeechSettings settings;

  @override
  Future<SpeechSettings> load() async => settings;

  @override
  Future<void> save(SpeechSettings settings) async {
    this.settings = settings;
  }
}

/// Scripted [SpeechService]: [start] reports [available], [stop] returns
/// the next entry of [answers] (or '' once they run out).
class FakeSpeechService implements SpeechService {
  FakeSpeechService({this.available = true, List<String>? answers})
    : answers = answers ?? [];

  bool available;
  final List<String> answers;

  /// Settings passed to every [start] call, in order.
  final started = <SpeechSettings>[];

  @override
  Future<bool> start(SpeechSettings settings) async {
    started.add(settings);
    return available;
  }

  @override
  Future<String> stop() async => answers.isEmpty ? '' : answers.removeAt(0);

  @override
  Future<void> cancel() async {}
}
