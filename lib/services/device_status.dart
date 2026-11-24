import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'speech_settings.dart';

/// Device facts that can get in the way of using the app.
/// Abstracted so widget tests can inject a fake.
abstract class DeviceStatus {
  /// Android battery saver: throttles the speech recognizer noticeably.
  Future<bool> isPowerSaveMode();

  /// Whether Google's servers are reachable (online recognition, Drive).
  Future<bool> isOnline();
}

class PlatformDeviceStatus implements DeviceStatus {
  static const _channel = MethodChannel('talksimple/device');

  @override
  Future<bool> isPowerSaveMode() async {
    try {
      return await _channel.invokeMethod<bool>('isPowerSaveMode') ?? false;
    } on Object {
      // Not on Android / channel missing: don't warn about what we can't see.
      return false;
    }
  }

  @override
  Future<bool> isOnline() async {
    try {
      final result = await InternetAddress.lookup(
        'www.googleapis.com',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty;
    } on Object {
      return false;
    }
  }
}

/// Something worth telling the caregiver, most important first.
enum Notice {
  speechNotSetUp(
    'Spracherkennung ist noch nicht eingerichtet.',
    action: 'Einrichten',
  ),
  offline(
    'Kein Internet: neue Symbole aus Drive und die Online-Spracherkennung '
    'gehen gerade nicht.',
  ),
  powerSave(
    'Energiesparmodus ist an: die Spracherkennung kann langsamer sein.',
  );

  const Notice(this.text, {this.action});

  final String text;

  /// Label of the button that fixes it, if the app can help.
  final String? action;
}

/// Collects the notices that apply right now.
Future<List<Notice>> collectNotices(
  DeviceStatus status,
  SpeechSettings settings,
) async {
  final results = await Future.wait([
    status.isOnline(),
    status.isPowerSaveMode(),
  ]);
  final online = results[0];
  final powerSave = results[1];
  return [
    if (!settings.configured) Notice.speechNotSetUp,
    if (!online) Notice.offline,
    if (powerSave) Notice.powerSave,
  ];
}
