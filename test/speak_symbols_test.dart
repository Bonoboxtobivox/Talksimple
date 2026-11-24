import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talksimple/models/symbol_tile.dart';
import 'package:talksimple/screens/speak_symbols_screen.dart';
import 'package:talksimple/services/favorites_store.dart';
import 'package:talksimple/services/sentence_words.dart';
import 'package:talksimple/services/speech_settings.dart';

import 'fakes.dart';

/// Has a symbol for every word except "jetzt"; records what was asked.
class _Lookup {
  final asked = <String>[];

  Future<SymbolTile?> call(String word) async {
    asked.add(word);
    if (word.toLowerCase() == 'jetzt') return null;
    return SymbolTile(label: word, imageFile: File('/s/$word.png'));
  }
}

void main() {
  group('sentenceWords', () {
    test('drops punctuation, keeps order, umlauts and spelling', () {
      expect(sentenceWords('Wir gehen jetzt essen, okay?'), [
        'Wir',
        'gehen',
        'jetzt',
        'essen',
        'okay',
      ]);
      expect(sentenceWords('Möchtest du Saft?'), ['Möchtest', 'du', 'Saft']);
    });

    test('keeps hyphenated words, drops stray dashes', () {
      expect(sentenceWords('Zuerst Zähne-putzen - dann Bett'), [
        'Zuerst',
        'Zähne-putzen',
        'dann',
        'Bett',
      ]);
    });

    test('limits very long sentences', () {
      final words = sentenceWords(List.filled(30, 'ja').join(' '));
      expect(words, hasLength(maxSentenceWords));
    });

    test('is empty for blank input', () {
      expect(sentenceWords('  ,  ! '), isEmpty);
    });
  });

  group('favorites', () {
    test('toggle adds on top and removes case-insensitively', () {
      var favorites = toggleFavorite(['Hallo'], 'Wir gehen essen');
      expect(favorites, ['Wir gehen essen', 'Hallo']);
      expect(isFavorite(favorites, ' wir GEHEN essen '), isTrue);

      favorites = toggleFavorite(favorites, 'wir gehen essen');
      expect(favorites, ['Hallo']);
    });

    test('file store round-trips and survives a corrupt file', () async {
      final dir = await Directory.systemTemp.createTemp('favorites');
      addTearDown(() => dir.delete(recursive: true));
      final store = await FileFavoritesStore.open(baseDir: dir);

      expect(await store.load(), isEmpty);
      await store.save(['Pause', 'Trinken']);
      expect(await store.load(), ['Pause', 'Trinken']);

      await File('${dir.path}/favorites.json').writeAsString('[kaputt');
      expect(await store.load(), isEmpty);
    });
  });

  group('SpeakSymbolsScreen', () {
    late _Lookup lookup;
    late FakeFavorites favorites;
    late FakeSpeechService speech;

    Widget app() => MaterialApp(
      home: SpeakSymbolsScreen(
        speechService: speech,
        openSettings: () async => FakeSpeechSettings(
          const SpeechSettings(localeId: 'de_AT', configured: true),
        ),
        lookupSymbol: lookup.call,
        openFavoritesStore: () async => favorites,
      ),
    );

    setUp(() {
      lookup = _Lookup();
      favorites = FakeFavorites();
      speech = FakeSpeechService(answers: ['Wir gehen jetzt essen']);
    });

    testWidgets('holding the mic turns speech into a symbol sentence', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Halten & sprechen'));
      await tester.pumpAndSettle();

      expect(speech.started.single.localeId, 'de_AT');
      expect(lookup.asked, ['Wir', 'gehen', 'jetzt', 'essen']);
      expect(find.text('Wir gehen jetzt essen'), findsOneWidget);
      // Words with a symbol show their label once; "jetzt" has no symbol
      // and is shown as big text plus its label.
      expect(find.text('gehen'), findsOneWidget);
      expect(find.text('jetzt'), findsNWidgets(2));
      expect(find.byType(Image), findsNWidgets(3));
    });

    testWidgets('a repeated word is only looked up once per session', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final state = tester.state<SpeakSymbolsScreenState>(
        find.byType(SpeakSymbolsScreen),
      );

      await state.showSentence('ich will Saft');
      await state.showSentence('ich will Wasser');
      await tester.pumpAndSettle();

      expect(lookup.asked, ['ich', 'will', 'Saft', 'Wasser']);
    });

    testWidgets('nothing understood shows a retry hint, no sentence', (
      tester,
    ) async {
      speech = FakeSpeechService(answers: ['']);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Halten & sprechen'));
      await tester.pumpAndSettle();

      expect(
        find.text('Nichts verstanden — nochmal versuchen.'),
        findsOneWidget,
      );
      expect(lookup.asked, isEmpty);
    });

    testWidgets('star saves a favourite that brings the sentence back', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final state = tester.state<SpeakSymbolsScreenState>(
        find.byType(SpeakSymbolsScreen),
      );
      await state.showSentence('Wir gehen essen');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Als Favorit speichern'));
      await tester.pumpAndSettle();
      expect(favorites.sentences, ['Wir gehen essen']);
      expect(find.byTooltip('Aus Favoriten entfernen'), findsOneWidget);

      // Show something else, then pick the favourite from the list.
      await state.showSentence('Pause');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Favoriten'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wir gehen essen'));
      await tester.pumpAndSettle();

      expect(find.text('Sprechen → Symbole'), findsOneWidget);
      expect(find.text('Wir gehen essen'), findsOneWidget);
      expect(find.text('essen'), findsOneWidget);
    });

    testWidgets('a favourite can be deleted from the list', (tester) async {
      favorites = FakeFavorites(['Pause', 'Trinken']);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Favoriten'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Favorit löschen').first);
      await tester.pumpAndSettle();

      expect(find.text('Pause'), findsNothing);
      expect(favorites.sentences, ['Trinken']);
    });
  });
}
