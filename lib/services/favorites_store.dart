import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Saved favourite sentences ("Wir gehen jetzt essen"), newest first.
/// Abstracted so widget tests can use an in-memory fake.
abstract class FavoritesRepository {
  Future<List<String>> load();

  Future<void> save(List<String> sentences);
}

class FileFavoritesStore implements FavoritesRepository {
  FileFavoritesStore._(this._file);

  /// [baseDir] overrides where data is stored; only meant for tests.
  static Future<FileFavoritesStore> open({Directory? baseDir}) async {
    final base = baseDir ?? await getApplicationDocumentsDirectory();
    return FileFavoritesStore._(File('${base.path}/favorites.json'));
  }

  final File _file;

  @override
  Future<List<String>> load() async {
    try {
      if (!await _file.exists()) return [];
      final raw = await _file.readAsString();
      if (raw.trim().isEmpty) return [];
      return (jsonDecode(raw) as List).cast<String>();
    } on FormatException {
      return [];
    }
  }

  @override
  Future<void> save(List<String> sentences) async {
    await _file.writeAsString(jsonEncode(sentences));
  }
}

/// Opens the favourites store used by the app.
Future<FavoritesRepository> openFavorites() => FileFavoritesStore.open();

/// Adds [sentence] at the top, or removes it if it is already a favourite
/// (compared case-insensitively, ignoring surrounding spaces). Returns the
/// new list; the input is not modified.
List<String> toggleFavorite(List<String> favorites, String sentence) {
  final key = sentence.trim().toLowerCase();
  final without = [
    for (final f in favorites)
      if (f.trim().toLowerCase() != key) f,
  ];
  if (without.length != favorites.length) return without;
  return [sentence.trim(), ...favorites];
}

/// Whether [sentence] is in [favorites] (same comparison as
/// [toggleFavorite]).
bool isFavorite(List<String> favorites, String sentence) {
  final key = sentence.trim().toLowerCase();
  return favorites.any((f) => f.trim().toLowerCase() == key);
}
