import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Looks up Metacom symbols in the user's Google Drive by name.
///
/// The symbols live in the `metabonsymbole` folder, sorted into one
/// subfolder per category (Lebensmittel_Trinken, Zeit, Tiere, ...). File
/// names are lowercase, umlauts are transliterated (`getraenk`, `weiss`),
/// variants are separated by `_` (`wein_rot`) and black-and-white versions
/// carry an `SW` suffix (`kaffeebohnenSW.png`).
///
/// Read-only, on demand: nothing is synced or cached beyond a single
/// downloaded match, and nothing here is ever committed to source control
/// - Metacom symbols are commercially licensed and stay in the account's
/// own Drive.
class DriveSymbolSource {
  DriveSymbolSource._();

  static final DriveSymbolSource instance = DriveSymbolSource._();

  /// The `metabonsymbole` folder holding the converted Metacom symbols.
  static const rootFolderId = '1ipBumsa-uhUPyjn3r_8qOoJAiZl4iwTa';
  static const _scopes = ['https://www.googleapis.com/auth/drive.readonly'];

  /// Max folders per Drive query: keeps the `q` parameter well below URL
  /// length limits even with ~60 category folders.
  static const _foldersPerQuery = 25;

  bool _initialized = false;
  GoogleSignInAccount? _account;

  /// Root + category subfolders, fetched once per app run.
  List<String>? _folderIds;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  Future<Map<String, String>?> _authHeaders() async {
    await _ensureInitialized();
    var account = _account ??= await GoogleSignIn.instance
        .attemptLightweightAuthentication();
    account ??= await GoogleSignIn.instance.authenticate();
    _account = account;
    return account.authorizationClient.authorizationHeaders(
      _scopes,
      promptIfNecessary: true,
    );
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

  /// Picks the best file name for [term] out of Drive's (fuzzy) matches,
  /// or null if none of them actually contains the term.
  ///
  /// Ranking: exact name before prefix before substring; the colour
  /// version before its `SW` (black-and-white) twin; then shorter names.
  static String? pickBest(String term, Iterable<String> fileNames) {
    String? best;
    var bestScore = -1 << 30;
    for (final name in fileNames) {
      final dot = name.lastIndexOf('.');
      var base = dot == -1 ? name : name.substring(0, dot);
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
        continue;
      }
      final score = matchScore - (isBlackWhite ? 500 : 0) - base.length;
      if (score > bestScore) {
        bestScore = score;
        best = name;
      }
    }
    return best;
  }

  Future<List<String>> _loadFolderIds(Map<String, String> headers) async {
    final cached = _folderIds;
    if (cached != null) return cached;

    final ids = <String>[rootFolderId];
    String? pageToken;
    var complete = true;
    do {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q':
            "'$rootFolderId' in parents and trashed = false and "
            "mimeType = 'application/vnd.google-apps.folder'",
        'fields': 'nextPageToken,files(id)',
        'pageSize': '1000',
        'pageToken': ?pageToken,
      });
      final response = await http.get(uri, headers: headers);
      if (response.statusCode != 200) {
        complete = false;
        break;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      for (final file in (data['files'] as List).cast<Map<String, dynamic>>()) {
        ids.add(file['id'] as String);
      }
      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null);

    // Only cache a complete listing; a failed one is retried next time.
    if (complete) _folderIds = ids;
    return ids;
  }

  /// Returns `{name: id}` for every image in the symbol folders whose name
  /// Drive considers to contain [term].
  Future<Map<String, String>> _searchImages(
    String term,
    List<String> folderIds,
    Map<String, String> headers,
  ) async {
    final results = <String, String>{};
    for (var i = 0; i < folderIds.length; i += _foldersPerQuery) {
      final chunk = folderIds.skip(i).take(_foldersPerQuery);
      final parents = chunk.map((id) => "'$id' in parents").join(' or ');
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q':
            "($parents) and trashed = false and "
            "mimeType contains 'image/' and name contains '$term'",
        'fields': 'files(id,name)',
        'pageSize': '50',
      });
      final response = await http.get(uri, headers: headers);
      if (response.statusCode != 200) continue;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      for (final file in (data['files'] as List).cast<Map<String, dynamic>>()) {
        results[file['name'] as String] = file['id'] as String;
      }
    }
    return results;
  }

  /// Searches the symbol folders for the best match for [word], downloads
  /// it, and returns it as a local temp file.
  ///
  /// Returns null on anything short of success - not signed in, no match,
  /// offline, permission denied - so callers can fall back to the camera
  /// without needing to distinguish why.
  Future<File?> findAndDownload(String word) async {
    try {
      // normalize() strips everything but [a-z0-9_-], so terms are safe to
      // embed in a Drive query without further escaping.
      final terms = searchTerms(word);
      if (terms.isEmpty) return null;

      final headers = await _authHeaders();
      if (headers == null) return null;
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

      final downloadUri = Uri.https(
        'www.googleapis.com',
        '/drive/v3/files/$fileId',
        {'alt': 'media'},
      );
      final downloadResponse = await http.get(downloadUri, headers: headers);
      if (downloadResponse.statusCode != 200) return null;

      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/drive_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(downloadResponse.bodyBytes);
      return tempFile;
    } catch (_) {
      return null;
    }
  }
}
