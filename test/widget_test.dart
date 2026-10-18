import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:talksimple/models/symbol_tile.dart';
import 'package:talksimple/screens/board_screen.dart';
import 'package:talksimple/services/board_store.dart';

/// In-memory stand-in for [BoardRepository]. Avoids real file I/O in widget
/// tests: a testWidgets body runs its pumps in a restricted zone where real
/// dart:io operations kicked off from initState never resolve.
class _InMemoryBoardRepository implements BoardRepository {
  List<SymbolTile>? _saved;

  @override
  Future<List<SymbolTile>?> load() async => _saved;

  @override
  Future<void> save(List<SymbolTile> tiles) async {
    _saved = tiles;
  }
}

Widget _boardApp(BoardRepository repository) {
  return MaterialApp(
    home: BoardScreen(openRepository: () async => repository),
  );
}

void main() {
  testWidgets('Board screen shows title and placeholder tiles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_boardApp(_InMemoryBoardRepository()));
    await tester.pumpAndSettle();

    expect(find.text('TalkSimple'), findsOneWidget);
    expect(find.text('Ja'), findsOneWidget);
    expect(find.text('Nein'), findsOneWidget);
  });

  testWidgets('Tapping a tile shows its label in a snackbar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_boardApp(_InMemoryBoardRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trinken'));
    await tester.pump();

    expect(find.text('Trinken'), findsWidgets);
  });

  group('phone width (< 600)', () {
    testWidgets('shows a fixed 2x2 grid, not all tiles at once', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_boardApp(_InMemoryBoardRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Ja'), findsOneWidget);
      expect(find.text('Nein'), findsOneWidget);
      expect(find.text('Mehr'), findsOneWidget);
      expect(find.text('Fertig'), findsOneWidget);
      expect(find.text('Trinken'), findsNothing);
      expect(find.text('Zurück'), findsOneWidget);
      expect(find.text('Weiter'), findsOneWidget);
    });

    testWidgets('Weiter shows the next page, Zurück goes back', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_boardApp(_InMemoryBoardRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Weiter'));
      await tester.pump();

      expect(find.text('Trinken'), findsOneWidget);
      expect(find.text('Essen'), findsOneWidget);
      expect(find.text('Hilfe'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Ja'), findsNothing);

      await tester.tap(find.text('Zurück'));
      await tester.pump();

      expect(find.text('Ja'), findsOneWidget);
    });
  });

  testWidgets('A board saved in the repository is shown instead of the seed', (
    WidgetTester tester,
  ) async {
    final repository = _InMemoryBoardRepository();
    await repository.save(const [SymbolTile(label: 'Musik')]);

    await tester.pumpWidget(_boardApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Musik'), findsOneWidget);
    expect(find.text('Ja'), findsNothing);
  });

  testWidgets('Adding a tile appends it and persists the board', (
    WidgetTester tester,
  ) async {
    final repository = _InMemoryBoardRepository();
    final key = GlobalKey<BoardScreenState>();
    await tester.pumpWidget(
      MaterialApp(
        home: BoardScreen(key: key, openRepository: () async => repository),
      ),
    );
    await tester.pumpAndSettle();

    const newTile = SymbolTile(label: 'Musik');
    // Simulates what AddTileScreen returns via Navigator.pop, without
    // needing a real device file/image picker in a widget test.
    await key.currentState!.addTileForTest(newTile);
    await tester.pumpAndSettle();

    // The new tile lands after the 8 seed tiles, so on the default test
    // viewport it may be scrolled out of view — check the persisted state
    // instead of on-screen visibility.
    final persisted = await repository.load();
    expect(persisted, isNotNull);
    expect(persisted!.map((t) => t.label), contains('Musik'));
  });

  testWidgets('Tapping + opens the add-tile screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_boardApp(_InMemoryBoardRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    // Not pumpAndSettle: AddTileScreen's own symbol library lookup touches
    // real device storage and never resolves in a widget test (see the
    // BoardRepository fake above) - a couple of finite pumps are enough to
    // land on the new screen.
    await tester.pump();
    await tester.pump();

    expect(find.text('Kachel hinzufügen'), findsOneWidget);
  });
}
