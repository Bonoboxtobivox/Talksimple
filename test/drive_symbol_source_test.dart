import 'package:flutter_test/flutter_test.dart';
import 'package:talksimple/services/drive_symbol_source.dart';

void main() {
  group('normalize', () {
    test('lowercases and transliterates umlauts like the symbol files', () {
      expect(DriveSymbolSource.normalize('Getränk'), 'getraenk');
      expect(DriveSymbolSource.normalize('Weiß'), 'weiss');
      expect(DriveSymbolSource.normalize('Größe Übung'), 'groesse_uebung');
    });

    test('turns whitespace into underscores and drops punctuation', () {
      expect(DriveSymbolSource.normalize('  Wein   rot! '), 'wein_rot');
      expect(DriveSymbolSource.normalize("Kaffee's"), 'kaffees');
    });
  });

  group('searchTerms', () {
    test('tries the whole word first, then its parts longest first', () {
      expect(DriveSymbolSource.searchTerms('Rotes Getränk'), [
        'rotes_getraenk',
        'getraenk',
        'rotes',
      ]);
    });

    test('returns a single term for a single word', () {
      expect(DriveSymbolSource.searchTerms('Trinken'), ['trinken']);
    });

    test('is empty for blank input', () {
      expect(DriveSymbolSource.searchTerms('   '), isEmpty);
    });
  });

  group('pickBest', () {
    test('prefers the exact name over longer matches', () {
      expect(
        DriveSymbolSource.pickBest('wein', [
          'wein_rot.png',
          'wein.png',
          'weinglas.png',
        ]),
        'wein.png',
      );
    });

    test('prefers the colour version over its SW twin', () {
      expect(
        DriveSymbolSource.pickBest('kaffeebohnen', [
          'kaffeebohnenSW.png',
          'kaffeebohnen.png',
        ]),
        'kaffeebohnen.png',
      );
    });

    test('still finds an SW-only symbol', () {
      expect(
        DriveSymbolSource.pickBest('kaffeepulver', ['kaffeepulverSW.png']),
        'kaffeepulverSW.png',
      );
    });

    test('prefers a prefix match, then the shortest name', () {
      expect(
        DriveSymbolSource.pickBest('wein', [
          'rotwein.png',
          'wein_weiss.png',
          'wein_rot.png',
        ]),
        'wein_rot.png',
      );
    });

    test('ignores files that do not contain the term at all', () {
      expect(
        DriveSymbolSource.pickBest('tee', ['kaffee.png', 'wasser.png']),
        isNull,
      );
    });
  });
}
