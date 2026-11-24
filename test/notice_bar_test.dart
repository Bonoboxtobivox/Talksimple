import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talksimple/screens/home_screen.dart';
import 'package:talksimple/screens/speak_symbols_screen.dart';
import 'package:talksimple/screens/speech_setup_screen.dart';
import 'package:talksimple/services/device_status.dart';
import 'package:talksimple/services/speech_settings.dart';
import 'package:talksimple/widgets/notice_bar.dart';

import 'fakes.dart';

void main() {
  group('collectNotices', () {
    test('nothing to say when set up, online and not saving power', () async {
      expect(
        await collectNotices(
          FakeDeviceStatus(),
          const SpeechSettings(configured: true),
        ),
        isEmpty,
      );
    });

    test('lists every problem, most important first', () async {
      expect(
        await collectNotices(
          FakeDeviceStatus(online: false, powerSave: true),
          const SpeechSettings(),
        ),
        [Notice.speechNotSetUp, Notice.offline, Notice.powerSave],
      );
    });
  });

  testWidgets('NoticeBar shows, acts on and dismisses notices', (tester) async {
    final actions = <Notice>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoticeBar(
            deviceStatus: FakeDeviceStatus(powerSave: true),
            openSettings: () async => FakeSpeechSettings(),
            onAction: actions.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(Notice.speechNotSetUp.text), findsOneWidget);
    expect(find.text(Notice.powerSave.text), findsOneWidget);
    expect(find.text(Notice.offline.text), findsNothing);

    await tester.tap(find.text('Einrichten'));
    expect(actions, [Notice.speechNotSetUp]);

    await tester.tap(find.byTooltip('Hinweis schließen').last);
    await tester.pumpAndSettle();
    expect(find.text(Notice.powerSave.text), findsNothing);
    expect(find.text(Notice.speechNotSetUp.text), findsOneWidget);
  });

  group('HomeScreen', () {
    Widget app(FakeSpeechSettings settings) => MaterialApp(
      home: HomeScreen(
        deviceStatus: FakeDeviceStatus(),
        openSettings: () async => settings,
      ),
    );

    testWidgets('offers speaking to symbols as the first choice', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(FakeSpeechSettings(const SpeechSettings(configured: true))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sprechen → Symbole'), findsOneWidget);
      await tester.tap(find.text('Sprechen → Symbole'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SpeakSymbolsScreen), findsOneWidget);
    });

    testWidgets('the setup notice opens the speech setup', (tester) async {
      await tester.pumpWidget(app(FakeSpeechSettings()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Einrichten'));
      await tester.pumpAndSettle();
      expect(find.byType(SpeechSetupScreen), findsOneWidget);
    });

    testWidgets('the notice disappears once setup is saved', (tester) async {
      final settings = FakeSpeechSettings();
      await tester.pumpWidget(app(settings));
      await tester.pumpAndSettle();
      expect(find.text(Notice.speechNotSetUp.text), findsOneWidget);

      await tester.tap(find.byTooltip('Spracherkennung einrichten'));
      await tester.pumpAndSettle();
      settings.settings = const SpeechSettings(configured: true);
      Navigator.of(tester.element(find.byType(SpeechSetupScreen))).pop();
      await tester.pumpAndSettle();

      expect(find.text(Notice.speechNotSetUp.text), findsNothing);
    });
  });
}
