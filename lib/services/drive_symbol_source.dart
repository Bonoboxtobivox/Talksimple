import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Why Drive could not deliver a symbol.
enum DriveProblem {
  /// No Google account chosen, access declined, or the app is not (yet)
  /// registered in the Google Cloud Console.
  notAuthorized(
    'Kein Zugriff auf Google Drive. Beim Anmelden das Google-Konto mit den '
    'Metacom-Symbolen wählen und den Zugriff erlauben.',
  ),

  /// No connection to Google.
  offline('Keine Verbindung zu Google Drive. Bitte Internet prüfen.');

  const DriveProblem(this.message);

  /// German explanation for the caregiver.
  final String message;
}

class DriveException implements Exception {
  const DriveException(this.problem);

  final DriveProblem problem;

  @override
  String toString() => 'DriveException(${problem.name})';
}

/// A category folder inside the symbol library (e.g. `Lebensmittel_Essen`).
class SymbolFolder {
  const SymbolFolder({required this.id, required this.name});

  final String id;
  final String name;

  /// `Lebensmittel_Essen` -> `Lebensmittel Essen`.
  String get displayName => name.replaceAll('_', ' ');
}

/// One symbol image file (e.g. `wein_rot.png`).
class SymbolEntry {
  const SymbolEntry({required this.id, required this.name});

  final String id;
  final String name;

  /// Black-and-white variant (`...SW.png`).
  bool get isBlackWhite => _base.endsWith('SW');

  /// `wein_rot.png` -> `wein rot`, `kaffeebohnenSW.png` -> `kaffeebohnen`.
  String get label {
    var base = _base;
    if (base.endsWith('SW')) base = base.substring(0, base.length - 2);
    return base.replaceAll('_', ' ').trim();
  }

  String get _base {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? name : name.substring(0, dot);
  }
}

/// Browsable symbol library: categories, their symbols, a search, and the
/// image bytes. Abstracted so widget tests can use an in-memory fake.
abstract class SymbolCatalog {
  /// Throws [DriveException] on failure, like [filesIn] and [search].
  Future<List<SymbolFolder>> folders();

  Future<List<SymbolEntry>> filesIn(String folderId);

  /// Best matches first.
  Future<List<SymbolEntry>> search(String word);

  /// Image bytes, or null if they could not be loaded.
  Future<Uint8List?> bytes(String fileId);
}

/// Metacom symbols in the user's Google Drive.
///
/// The symbols live in the `metabonsymbole` folder, sorted into one
/// subfolder per category (Lebensmittel_Trinken, Zeit, Tiere, ...). File
/// names are lowercase, umlauts are transliterated (`getraenk`, `weiss`),
/// variants are separated by `_` (`wein_rot`) and black-and-white versions
/// carry an `SW` suffix (`kaffeebohnenSW.png`).
///
/// Read-only, on demand: nothing is committed to source control - Metacom
/// symbols are commercially licensed and stay in the account's own Drive.
class DriveSymbolSource implements SymbolCatalog {
  DriveSymbolSource._();

  static final DriveSymbolSource instance = DriveSymbolSource._();

  /// The `metabonsymbole` folder holding the converted Metacom symbols.
  static const rootFolderId = '1ipBumsa-uhUPyjn3r_8qOoJAiZl4iwTa';
  static const _scopes = ['https://www.googleapis.com/auth/drive.readonly'];

  /// Max folders per Drive query: keeps the `q` parameter well below URL
  /// length limits even with ~60 category folders.
  static const _foldersPerQuery = 25;

  bool _initialized = false;

  /// Root + category subfolders, fetched once per app run.
  List<String>? _folderIds;

  /// Downloaded images by file id, so browsing back and forth does not
  /// download the same picture twice.
  final Map<String, Future<Uint8List?>> _bytesCache = {};

  /// Why the last [findAndDownload] found nothing, or null if the search
  /// itself worked. Lets the UI say "Drive not connected" instead of
  /// silently falling back to the camera.
  DriveProblem? lastProblem;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  /// Authorization headers for read-only Drive access.
  ///
  /// Deliberately no `authenticate()` first: on Android that sign-in needs
  /// a web OAuth client id (serverClientId) and always failed without one.
  /// Plain authorization only needs the Android OAuth client (package name
  /// + SHA-1) and shows Google's account chooser by itself.
  Future<Map<String, String>> _authHeaders() async {
    try {
      await _ensureInitialized();
      final headers = await GoogleSignIn.instance.authorizationClient
          .authorizationHeaders(_scopes, promptIfNecessary: true);
      if (headers == null) {
        throw const DriveException(DriveProblem.notAuthorized);
      }
      return headers;
    } on DriveException {
      rethrow;
    } on SocketException {
      throw const DriveException(DriveProblem.offline);
    } catch (_) {
      throw const DriveException(DriveProblem.notAuthorized);
    }
  }

  /// GET against the Drive API; maps every failure to [DriveException].
  Future<http.Response> _get(Uri uri, Map<String, String> headers) async {
    final http.Response response;
    try {
      response = await http.get(uri, headers: headers);
    } on SocketException {
      throw const DriveException(DriveProblem.offline);
    } on http.ClientException {
      throw const DriveException(DriveProblem.offline);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const DriveException(DriveProblem.notAuthorized);
    }
    if (response.statusCode != 200) {
      throw const DriveException(DriveProblem.offline);
    }
    return response;
  }

  /// All files matching a Drive query, following every result page.
  Future<List<Map<String, dynamic>>> _list(
    String query,
    Map<String, String> headers, {
    int pageSize = 1000,
    bool allPages = true,
  }) async {
    final files = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': query,
        'fields': 'nextPageToken,files(id,name)',
        'orderBy': 'name',
        'pageSize': '$pageSize',
        'pageToken': ?pageToken,
      });
      final data =
          jsonDecode((await _get(uri, headers)).body) as Map<String, dynamic>;
      files.addAll((data['files'] as List).cast<Map<String, dynamic>>());
      pageToken = allPages ? data['nextPageToken'] as String? : null;
    } while (pageToken != null);
    return files;
  }

  @override
  Future<List<SymbolFolder>> folders() async {
    final headers = await _authHeaders();
    final files = await _list(
      "'$rootFolderId' in parents and trashed = false and "
      "mimeType = 'application/vnd.google-apps.folder'",
      headers,
    );
    return [
      for (final f in files)
        SymbolFolder(id: f['id'] as String, name: f['name'] as String),
    ];
  }

  @override
  Future<List<SymbolEntry>> filesIn(String folderId) async {
    final headers = await _authHeaders();
    final files = await _list(
      "'$folderId' in parents and trashed = false and "
      "mimeType contains 'image/'",
      headers,
    );
    return [
      for (final f in files)
        SymbolEntry(id: f['id'] as String, name: f['name'] as String),
    ];
  }

  @override
  Future<List<SymbolEntry>> search(String word) async {
    final terms = searchTerms(word);
    if (terms.isEmpty) return const [];
    final headers = await _authHeaders();
    final folderIds = await _loadFolderIds(headers);
    final found = <String, String>{};
    for (final term in terms) {
      found.addAll(await _searchImages(term, folderIds, headers));
    }
    // Whole-word matches by rank, then matches of single parts by name.
    final ranked = rank(terms.first, found.keys);
    final rest = found.keys.where((n) => !ranked.contains(n)).toList()..sort();
    return [
      for (final name in [...ranked, ...rest])
        SymbolEntry(id: found[name]!, name: name),
    ];
  }

  @override
  Future<Uint8List?> bytes(String fileId) {
    return _bytesCache[fileId] ??= () async {
      try {
        final headers = await _authHeaders();
        final uri = Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
          'alt': 'media',
        });
        return (await _get(uri, headers)).bodyBytes;
      } catch (_) {
        // Allow a retry later instead of caching the failure.
        _bytesCache.remove(fileId);
        return null;
      }
    }();
  }

  /// Turns a spoken/typed word into the file-name form used in the symbol
  /// folders: lowercase, umlauts transliterated, whitespace as `_`.
  ///
  /// `"Rotes Getränk"` -> `"rotes_getraenk"`.
  static String normalize(String word) {
    return word
        .trim()
        .toLowerCase()
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-z0-9_\-]'), '');
  }

  /// Search terms to try in order: the whole normalized word first, then
  /// its single parts, longest first (`"rotes_getraenk"` -> also
  /// `"getraenk"`, `"rotes"`).
  static List<String> searchTerms(String word) {
    final normalized = normalize(word);
    if (normalized.isEmpty) return const [];
    final parts =
        normalized
            .split('_')
            .where((p) => p.length >= 3 && p != normalized)
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    return [normalized, ...parts];
  }

  /// How well [fileName] matches [term], or null if it does not contain
  /// it. Exact name before prefix before substring; the colour version
  /// before its `SW` (black-and-white) twin; then shorter names.
  static int? score(String term, String fileName) {
    final dot = fileName.lastIndexOf('.');
    var base = dot == -1 ? fileName : fileName.substring(0, dot);
    final isBlackWhite = base.endsWith('SW');
    if (isBlackWhite) base = base.substring(0, base.length - 2);
    base = base.toLowerCase();

    final int matchScore;
    if (base == term) {
      matchScore = 3000;
    } else if (base.startsWith(term)) {
      matchScore = 2000;
    } else if (base.contains(term)) {
      matchScore = 1000;
    } else {
      return null;
    }
    return matchScore - (isBlackWhite ? 500 : 0) - base.length;
  }

  /// The file names containing [term], best match first.
  static List<String> rank(String term, Iterable<String> fileNames) {
    final scored = [
      for (final name in fileNames)
        if (score(term, name) case final s?) (name: name, score: s),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return [for (final s in scored) s.name];
  }

  /// The best file name for [term], or null if none contains it.
  static String? pickBest(String term, Iterable<String> fileNames) {
    final ranked = rank(term, fileNames);
    return ranked.isEmpty ? null : ranked.first;
  }

  Future<List<String>> _loadFolderIds(Map<String, String> headers) async {
    final cached = _folderIds;
    if (cached != null) return cached;
    final folders = await _list(
      "'$rootFolderId' in parents and trashed = false and "
      "mimeType = 'application/vnd.google-apps.folder'",
      headers,
    );
    return _folderIds = [
      rootFolderId,
      for (final f in folders) f['id'] as String,
    ];
  }

  /// Returns `{name: id}` for every image in the symbol folders whose name
  /// Drive considers to contain [term]. [term] comes from [normalize], so
  /// it only holds `[a-z0-9_-]` and is safe inside the query.
  Future<Map<String, String>> _searchImages(
    String term,
    List<String> folderIds,
    Map<String, String> headers,
  ) async {
    final results = <String, String>{};
    for (var i = 0; i < folderIds.length; i += _foldersPerQuery) {
      final chunk = folderIds.skip(i).take(_foldersPerQuery);
      final parents = chunk.map((id) => "'$id' in parents").join(' or ');
      final files = await _list(
        "($parents) and trashed = false and "
        "mimeType contains 'image/' and name contains '$term'",
        headers,
        pageSize: 50,
        allPages: false,
      );
      for (final file in files) {
        results[file['name'] as String] = file['id'] as String;
      }
    }
    return results;
  }

  /// Searches the symbol folders for the best match for [word], downloads
  /// it, and returns it as a local temp file.
  ///
  /// Returns null on anything short of success, so callers can fall back
  /// to the camera; [lastProblem] tells them why when it was not simply
  /// "no such symbol".
  Future<File?> findAndDownload(String word) async {
    lastProblem = null;
    try {
      final terms = searchTerms(word);
      if (terms.isEmpty) return null;

      final headers = await _authHeaders();
      final folderIds = await _loadFolderIds(headers);

      String? fileId;
      for (final term in terms) {
        final matches = await _searchImages(term, folderIds, headers);
        final bestName = pickBest(term, matches.keys);
        if (bestName != null) {
          fileId = matches[bestName];
          break;
        }
      }
      if (fileId == null) return null;

      final data = await bytes(fileId);
      if (data == null) return null;
      return await writeTempImage(data);
    } on DriveException catch (e) {
      lastProblem = e.problem;
      return null;
    } catch (_) {
      lastProblem = DriveProblem.offline;
      return null;
    }
  }
}

/// Writes downloaded image bytes to a temp file (the symbol library then
/// copies it into permanent storage).
Future<File> writeTempImage(Uint8List data) async {
  final tempDir = await getTemporaryDirectory();
  final file = File(
    '${tempDir.path}/symbol_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(data);
  return file;
}
