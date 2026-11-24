import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talksimple/screens/speech_setup_screen.dart';
import 'package:talksimple/services/speech_settings.dart';
import 'package:talksimple/widgets/empty_tile_picker.dart';

import 'fakes.dart';

/// A tall phone-sized viewport, so all three setup steps fit on screen.
void _useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Scrolls [finder] into the visible part of the list, then taps it.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

Widget _setupApp(FakeSpeechSettings store, FakeSpeechService speech) {
  return MaterialApp(
    home: SpeechSetupScreen(
      openSettings: () async => store,
      speechService: speech,
    ),
  );
}

void main() {
  group('SpeechSettings', () {
    test('defaults to unconfigured German online recognition', () {
      const settings = SpeechSettings();
      expect(settings.localeId, 'de_DE');
      expect(settings.onDevice, isFalse);
      expect(settings.configured, isFalse);
    });

    test('file store round-trips and survives a corrupt file', () async {
      final dir = await Directory.systemTemp.createTemp('speech_settings');
      addTearDown(() => dir.delete(recursive: true));
      final store = await FileSpeechSettingsStore.open(baseDir: dir);

      expect((await store.load()).configured, isFalse);

      await store.save(
        const SpeechSettings(
          localeId: 'de_AT',
          onDevice: true,
          configured: true,
        ),
      );
      final loaded = await store.load();
      expect(loaded.localeId, 'de_AT');
      expect(loaded.onDevice, isTrue);
      expect(loaded.configured, isTrue);
      expect(loaded.variantLabel, 'Deutsch (Österreich)');

      await File('${dir.path}/speech_settings.json').writeAsString('{kaputt');
      expect((await store.load()).localeId, 'de_DE');
    });
  });

  group('SpeechSetupScreen', () {
    testWidgets('Fertig is locked until a successful test, then saves', (
      tester,
    ) async {
      _useTallScreen(tester);
      final store = FakeSpeechSettings();
      final speech = FakeSpeechService(answers: ['Hallo Sophie']);
      await tester.pumpWidget(_setupApp(store, speech));
      await tester.pumpAndSettle();

      final finish = find.widgetWithText(FilledButton, 'Bitte zuerst testen');
      expect(tester.widget<FilledButton>(finish).onPressed, isNull);

      await _tapVisible(tester, find.text('Deutsch (Österreich)'));
      await _tapVisible(tester, find.text('Ohne Internet (empfohlen)'));
      await tester.pump();

      await _tapVisible(tester, find.text('Jetzt testen'));
      await tester.pump();
      expect(find.text('Ich höre zu …'), findsOneWidget);
      expect(speech.started.single.localeId, 'de_AT');
      expect(speech.started.single.onDevice, isTrue);

      await _tapVisible(tester, find.text('Fertig gesprochen'));
      await tester.pump();
      expect(
        find.text('Funktioniert! Erkannt: „Hallo Sophie“'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Fertig'));
      await tester.pumpAndSettle();
      expect(store.settings.configured, isTrue);
      expect(store.settings.localeId, 'de_AT');
      expect(store.settings.onDevice, isTrue);
    });

    testWidgets('a failed offline test explains the missing language pack', (
      tester,
    ) async {
      _useTallScreen(tester);
      final speech = FakeSpeechService(answers: ['']);
      await tester.pumpWidget(
        _setupApp(
          FakeSpeechSettings(const SpeechSettings(onDevice: true)),
          speech,
        ),
      );
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('Jetzt testen'));
      await tester.pump();
      await _tapVisible(tester, find.text('Fertig gesprochen'));
      await tester.pump();

      expect(find.textContaining('Offline-Sprachpaket fehlt'), findsOneWidget);
    });

    testWidgets('changing the variant invalidates an earlier test', (
      tester,
    ) async {
      _useTallScreen(tester);
      final speech = FakeSpeechService(answers: ['Test']);
      await tester.pumpWidget(_setupApp(FakeSpeechSettings(), speech));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('Jetzt testen'));
      await tester.pump();
      await _tapVisible(tester, find.text('Fertig gesprochen'));
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Fertig'), findsOneWidget);

      await _tapVisible(tester, find.text('Deutsch (Schweiz)'));
      await tester.pump();
      expect(
        find.widgetWithText(FilledButton, 'Bitte zuerst testen'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the tile picker listens with the saved variant and mode', (
    tester,
  ) async {
    final speech = FakeSpeechService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyTilePicker(
            onResolved: (_) {},
            speechService: speech,
            openSettings: () async => FakeSpeechSettings(
              const SpeechSettings(localeId: 'de_AT', onDevice: true),
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.byIcon(Icons.mic_none_outlined));
    await tester.pump();

    expect(speech.started.single.localeId, 'de_AT');
    expect(speech.started.single.onDevice, isTrue);
  });
}
