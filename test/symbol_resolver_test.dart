import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:talksimple/models/symbol_tile.dart';
import 'package:talksimple/services/symbol_resolver.dart';

void main() {
  group('fillMissingSymbols', () {
    test('fills tiles without image and keeps their own label', () async {
      final result = await fillMissingSymbols(
        const [SymbolTile(label: 'Ja'), SymbolTile(label: 'Nein')],
        (word) async =>
            SymbolTile(label: 'other', imageFile: File('/symbols/$word.png')),
      );

      expect(result.filled, 2);
      expect(result.missing, 0);
      expect(result.tiles.map((t) => t.label), ['Ja', 'Nein']);
      expect(result.tiles.map((t) => t.imageFile?.path), [
        '/symbols/Ja.png',
        '/symbols/Nein.png',
      ]);
    });

    test('leaves tiles that already have an image untouched', () async {
      final looked = <String>[];
      final result = await fillMissingSymbols(
        [
          SymbolTile(label: 'Foto', imageFile: File('/own/foto.jpg')),
          const SymbolTile(label: 'Mehr'),
        ],
        (word) async {
          looked.add(word);
          return SymbolTile(label: word, imageFile: File('/s/$word.png'));
        },
      );

      expect(looked, ['Mehr']);
      expect(result.tiles.first.imageFile?.path, '/own/foto.jpg');
      expect(result.filled, 1);
    });

    test('counts words without a symbol as missing, keeps order', () async {
      final result = await fillMissingSymbols(
        const [
          SymbolTile(label: 'Ja'),
          SymbolTile(label: 'Xyz'),
          SymbolTile(label: 'Fertig'),
        ],
        (word) async => word == 'Xyz'
            ? null
            : SymbolTile(label: word, imageFile: File('/s/$word.png')),
      );

      expect(result.filled, 2);
      expect(result.missing, 1);
      expect(result.tiles.map((t) => t.label), ['Ja', 'Xyz', 'Fertig']);
      expect(result.tiles[1].imageFile, isNull);
    });
  });
}
