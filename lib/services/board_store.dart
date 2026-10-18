import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/symbol_tile.dart';

/// Where the current board's tiles are persisted, so tiles added on-device
/// survive an app restart. Abstracted so widget tests can inject an
/// in-memory fake instead of touching real device storage.
abstract class BoardRepository {
  /// Returns null if no board has been saved yet (first run).
  Future<List<SymbolTile>?> load();

  Future<void> save(List<SymbolTile> tiles);
}

class FileBoardStore implements BoardRepository {
  FileBoardStore._(this._file);

  /// [baseDir] overrides where data is stored; only meant for tests. In the
  /// app itself it always resolves to the real app documents directory.
  static Future<FileBoardStore> open({Directory? baseDir}) async {
    final base = baseDir ?? await getApplicationDocumentsDirectory();
    return FileBoardStore._(File('${base.path}/board.json'));
  }

  final File _file;

  @override
  Future<List<SymbolTile>?> load() async {
    if (!await _file.exists()) return null;
    final raw = await _file.readAsString();
    if (raw.trim().isEmpty) return null;
    final entries = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return [
      for (final entry in entries)
        SymbolTile(
          label: entry['label'] as String,
          imageFile: entry['path'] == null
              ? null
              : File(entry['path'] as String),
        ),
    ];
  }

  @override
  Future<void> save(List<SymbolTile> tiles) async {
    final entries = [
      for (final tile in tiles) {'label': tile.label, 'path': tile.imageFile?.path},
    ];
    await _file.writeAsString(jsonEncode(entries));
  }
}
