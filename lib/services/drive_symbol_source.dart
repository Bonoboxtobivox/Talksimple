import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Looks up Metacom symbols in the shared Google Drive folder by name.
///
/// Read-only, on demand: nothing is synced or cached beyond a single
/// downloaded match, and nothing here is ever committed to source control
/// - Metacom symbols stay wherever the account's Drive puts them.
class DriveSymbolSource {
  DriveSymbolSource._();

  static final DriveSymbolSource instance = DriveSymbolSource._();

  /// The folder shared for TalkSimple's Metacom symbols.
  static const _folderId = '19KLfZLuP4qKNbHeMk4AxR8ER2If_MIks';
  static const _scopes = ['https://www.googleapis.com/auth/drive.readonly'];

  bool _initialized = false;
  GoogleSignInAccount? _account;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  Future<Map<String, String>?> _authHeaders() async {
    await _ensureInitialized();
    var account =
        _account ??= await GoogleSignIn.instance
            .attemptLightweightAuthentication();
    account ??= await GoogleSignIn.instance.authenticate();
    _account = account;
    return account.authorizationClient.authorizationHeaders(
      _scopes,
      promptIfNecessary: true,
    );
  }

  /// Searches the shared folder for a file whose name contains [word],
  /// downloads the first match, and returns it as a local temp file.
  ///
  /// Returns null on anything short of success - not signed in, no match,
  /// offline, permission denied - so callers can fall back to the camera
  /// without needing to distinguish why.
  Future<File?> findAndDownload(String word) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return null;

      final escaped = word.replaceAll("'", "\\'");
      final listUri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q':
            "'$_folderId' in parents and trashed = false and "
            "name contains '$escaped'",
        'fields': 'files(id,name)',
        'pageSize': '5',
      });
      final listResponse = await http.get(listUri, headers: headers);
      if (listResponse.statusCode != 200) return null;

      final data = jsonDecode(listResponse.body) as Map<String, dynamic>;
      final files = (data['files'] as List).cast<Map<String, dynamic>>();
      if (files.isEmpty) return null;
      final fileId = files.first['id'] as String;

      final downloadUri = Uri.https(
        'www.googleapis.com',
        '/drive/v3/files/$fileId',
        {'alt': 'media'},
      );
      final downloadResponse = await http.get(downloadUri, headers: headers);
      if (downloadResponse.statusCode != 200) return null;

      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/drive_${DateTime.now().microsecondsSinceEpoch}',
      );
      await tempFile.writeAsBytes(downloadResponse.bodyBytes);
      return tempFile;
    } catch (_) {
      return null;
    }
  }
}
