import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/symbol_tile.dart';

/// Persists imported symbol images (Metacom symbols, own photos) on-device
/// so they can be reused across tiles and board sessions.
///
/// Images are copied into the app's own document storage — never bundled
/// into the app or committed to source control, since symbol sets like
/// Metacom are commercially licensed and must not be redistributed.
class SymbolLibrary {
  SymbolLibrary._(this._symbolsDir, this._manifestFile);

  /// [baseDir] overrides where data is stored; only meant for tests. In the
  /// app itself it always resolves to the real app documents directory.
  static Future<SymbolLibrary> open({Directory? baseDir}) async {
    final base = baseDir ?? await getApplicationDocumentsDirectory();
    final symbolsDir = Directory('${base.path}/symbols');
    if (!await symbolsDir.exists()) {
      await symbolsDir.create(recursive: true);
    }
    final manifestFile = File('${base.path}/symbol_library.json');
    return SymbolLibrary._(symbolsDir, manifestFile);
  }

  final Directory _symbolsDir;
  final File _manifestFile;

  Future<List<SymbolTile>> loadAll() async {
    final entries = await _readManifest();
    return [
      for (final entry in entries)
        SymbolTile(
          label: entry['label'] as String,
          imageFile: File(entry['path'] as String),
        ),
    ];
  }

  /// Copies the file at [sourcePath] into local storage under [label] and
  /// adds it to the library. Returns the resulting tile.
  Future<SymbolTile> import({
    required String sourcePath,
    required String label,
  }) async {
    final dotIndex = sourcePath.lastIndexOf('.');
    final extension = dotIndex == -1 ? 'img' : sourcePath.substring(dotIndex + 1);
    final fileName = '${DateTime.now().microsecondsSinceEpoch}.$extension';
    final destination = File('${_symbolsDir.path}/$fileName');
    await destination.writeAsBytes(await File(sourcePath).readAsBytes());

    final entries = await _readManifest();
    entries.add({'label': label, 'path': destination.path});
    await _writeManifest(entries);

    return SymbolTile(label: label, imageFile: destination);
  }

  Future<List<Map<String, dynamic>>> _readManifest() async {
    if (!await _manifestFile.exists()) return [];
    final raw = await _manifestFile.readAsString();
    if (raw.trim().isEmpty) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> _writeManifest(List<Map<String, dynamic>> entries) async {
    await _manifestFile.writeAsString(jsonEncode(entries));
  }
}
