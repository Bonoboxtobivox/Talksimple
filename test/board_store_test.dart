import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:talksimple/models/symbol_tile.dart';
import 'package:talksimple/services/board_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('talksimple_board_store_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('load() returns null when nothing was saved yet', () async {
    final store = await FileBoardStore.open(baseDir: tempDir);

    expect(await store.load(), isNull);
  });

  test('save() then load() round-trips the tile labels', () async {
    final store = await FileBoardStore.open(baseDir: tempDir);

    await store.save(const [SymbolTile(label: 'Ja'), SymbolTile(label: 'Nein')]);
    final loaded = await store.load();

    expect(loaded, isNotNull);
    expect(loaded!.map((t) => t.label), ['Ja', 'Nein']);
  });
}
