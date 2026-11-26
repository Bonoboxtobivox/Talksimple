import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talksimple/models/symbol_tile.dart';
import 'package:talksimple/screens/metacom_browser_screen.dart';
import 'package:talksimple/screens/speak_symbols_screen.dart';
import 'package:talksimple/services/drive_symbol_source.dart';

import 'fakes.dart';

/// A valid 1x1 transparent PNG.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _FakeCatalog implements SymbolCatalog {
  _FakeCatalog({this.problem});

  /// If set, every listing fails with this problem.
  DriveProblem? problem;
  final searched = <String>[];

  void _check() {
    if (problem != null) throw DriveException(problem!);
  }

  @override
  Future<List<SymbolFolder>> folders() async {
    _check();
    return const [
      SymbolFolder(id: 'f1', name: 'Wetter_Himmel'),
      SymbolFolder(id: 'f2', name: 'Zeit'),
    ];
  }

  @override
  Future<List<SymbolEntry>> filesIn(String folderId) async {
    _check();
    return folderId == 'f1'
        ? const [
            SymbolEntry(id: 's1', name: 'schnee.png'),
            SymbolEntry(id: 's2', name: 'sonne_scheint.png'),
          ]
        : const [SymbolEntry(id: 'z1', name: 'uhr.png')];
  }

  @override
  Future<List<SymbolEntry>> search(String word) async {
    _check();
    searched.add(word);
    return word.toLowerCase().startsWith('schnee')
        ? const [
            SymbolEntry(id: 's1', name: 'schnee.png'),
            SymbolEntry(id: 's3', name: 'schneemannSW.png'),
          ]
        : const [];
  }

  @override
  Future<Uint8List?> bytes(String fileId) async => _png;
}

/// Opens the browser from a button and records what it pops.
Widget _host(_FakeCatalog catalog, List<PickedSymbol?> results, {String? q}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              results.add(
                await Navigator.of(context).push<PickedSymbol>(
                  MaterialPageRoute(
                    builder: (_) =>
                        MetacomBrowserScreen(catalog: catalog, initialQuery: q),
                  ),
                ),
              );
            },
            child: const Text('öffnen'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('symbol names', () {
    test('entries turn file names into readable labels', () {
      const color = SymbolEntry(id: '1', name: 'wein_rot.png');
      const bw = SymbolEntry(id: '2', name: 'kaffeebohnenSW.png');
      expect(color.label, 'wein rot');
      expect(color.isBlackWhite, isFalse);
      expect(bw.label, 'kaffeebohnen');
      expect(bw.isBlackWhite, isTrue);
      expect(
        const SymbolFolder(id: 'x', name: 'Lebensmittel_Essen').displayName,
        'Lebensmittel Essen',
      );
    });

    test('rank orders exact, prefix, substring, colour before SW', () {
      expect(
        DriveSymbolSource.rank('wein', [
          'rotwein.png',
          'weinSW.png',
          'wein_rot.png',
          'wein.png',
          'kaffee.png',
        ]),
        ['wein.png', 'weinSW.png', 'wein_rot.png', 'rotwein.png'],
      );
    });
  });

  group('MetacomBrowserScreen', () {
    testWidgets('browse a category and pick a symbol', (tester) async {
      final results = <PickedSymbol?>[];
      await tester.pumpWidget(_host(_FakeCatalog(), results));
      await tester.tap(find.text('öffnen'));
      await tester.pumpAndSettle();

      expect(find.text('Metacom-Bibliothek'), findsOneWidget);
      expect(find.text('Wetter Himmel'), findsOneWidget);

      await tester.tap(find.text('Wetter Himmel'));
      await tester.pumpAndSettle();
      expect(find.text('schnee'), findsOneWidget);
      expect(find.text('sonne scheint'), findsOneWidget);

      await tester.tap(find.text('sonne scheint'));
      await tester.pumpAndSettle();

      expect(results.single!.label, 'sonne scheint');
      expect(results.single!.bytes, _png);
    });

    testWidgets('back inside a category returns to the category list', (
      tester,
    ) async {
      final results = <PickedSymbol?>[];
      await tester.pumpWidget(_host(_FakeCatalog(), results));
      await tester.tap(find.text('öffnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zeit'));
      await tester.pumpAndSettle();
      expect(find.text('uhr'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Wetter Himmel'), findsOneWidget);
      expect(results, isEmpty);
    });

    testWidgets('opens pre-searched for a word', (tester) async {
      final catalog = _FakeCatalog();
      final results = <PickedSymbol?>[];
      await tester.pumpWidget(_host(catalog, results, q: 'Schnee'));
      await tester.tap(find.text('öffnen'));
      await tester.pumpAndSettle();

      expect(catalog.searched, ['Schnee']);
      expect(find.text('schneemann'), findsOneWidget);

      await tester.tap(find.text('schnee'));
      await tester.pumpAndSettle();
      expect(results.single!.label, 'schnee');
    });

    testWidgets('an unknown word says so', (tester) async {
      await tester.pumpWidget(_host(_FakeCatalog(), [], q: 'Xylophon'));
      await tester.tap(find.text('öffnen'));
      await tester.pumpAndSettle();

      expect(find.text('Kein Symbol für „Xylophon“ gefunden.'), findsOneWidget);
    });

    testWidgets('a Drive problem is explained, with a retry', (tester) async {
      final catalog = _FakeCatalog(problem: DriveProblem.notAuthorized);
      await tester.pumpWidget(_host(catalog, []));
      await tester.tap(find.text('öffnen'));
      await tester.pumpAndSettle();

      expect(find.text(DriveProblem.notAuthorized.message), findsOneWidget);

      catalog.problem = null;
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();
      expect(find.text('Wetter Himmel'), findsOneWidget);
    });
  });

  testWidgets('tapping a word without symbol lets the caregiver pick one', (
    tester,
  ) async {
    final asked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SpeakSymbolsScreen(
          speechService: FakeSpeechService(),
          openSettings: () async => FakeSpeechSettings(),
          openFavoritesStore: () async => FakeFavorites(),
          lookupSymbol: (word) async => null,
          chooseSymbol: (context, word) async {
            asked.add(word);
            return SymbolTile(label: word, imageFile: File('/s/schnee.png'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<SpeakSymbolsScreenState>(
      find.byType(SpeakSymbolsScreen),
    );
    await state.showSentence('Schnee');
    await tester.pumpAndSettle();

    expect(
      find.text('Tippe auf ein Wort ohne Bild, um eines auszuwählen.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.pumpAndSettle();

    expect(asked, ['Schnee']);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing);
    expect(
      find.text('Tippe auf ein Wort ohne Bild, um eines auszuwählen.'),
      findsNothing,
    );
  });
}
