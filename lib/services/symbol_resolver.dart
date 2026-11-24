import '../models/symbol_tile.dart';
import 'drive_symbol_source.dart';
import 'symbol_library.dart';

/// Finds a symbol image for a word. Returns null if there is none.
typedef SymbolLookup = Future<SymbolTile?> Function(String word);

/// Looks a word up the same way everywhere in the app: first the on-device
/// symbol library (case-insensitive), then the Metacom folder in Google
/// Drive. A Drive match is imported into the library, so the next lookup
/// for the same word works offline.
///
/// [onSearchingDrive] fires right before the (slower) Drive search, so a
/// caller can update its status text.
Future<SymbolTile?> resolveSymbol(
  String word, {
  void Function()? onSearchingDrive,
}) async {
  final library = await SymbolLibrary.open();
  final wanted = word.toLowerCase();
  for (final entry in await library.loadAll()) {
    if (entry.label.toLowerCase() == wanted) return entry;
  }

  onSearchingDrive?.call();
  final driveFile = await DriveSymbolSource.instance.findAndDownload(word);
  if (driveFile == null) return null;
  return library.import(sourcePath: driveFile.path, label: word);
}

/// Result of [fillMissingSymbols].
class FillResult {
  const FillResult({
    required this.tiles,
    required this.filled,
    required this.missing,
  });

  /// All tiles, in their original order, with found images filled in.
  final List<SymbolTile> tiles;

  /// How many tiles got an image.
  final int filled;

  /// How many tiles still have none.
  final int missing;
}

/// Gives every tile without an image the symbol [lookup] finds for its
/// label. Tiles that already have an image are left untouched, and every
/// tile keeps its own label (so "Ja" stays "Ja" even if the file is
/// `ja_nicken.png`).
Future<FillResult> fillMissingSymbols(
  List<SymbolTile> tiles,
  SymbolLookup lookup,
) async {
  var filled = 0;
  var missing = 0;
  final result = <SymbolTile>[];
  for (final tile in tiles) {
    if (tile.imageFile != null) {
      result.add(tile);
      continue;
    }
    final found = await lookup(tile.label);
    if (found?.imageFile == null) {
      missing++;
      result.add(tile);
    } else {
      filled++;
      result.add(SymbolTile(label: tile.label, imageFile: found!.imageFile));
    }
  }
  return FillResult(tiles: result, filled: filled, missing: missing);
}
