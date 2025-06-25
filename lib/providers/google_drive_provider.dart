import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:googleapis_auth/auth_io.dart';

// Custom HTTP client for Google APIs to add auth headers
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}

class GoogleDriveService {
  // This is the Web Client ID from your Google Cloud Console.
  // It's required for Google Sign-In to work correctly with backend services like Google Drive.
  static const _webClientId = "920171293642-pqgepppbncii737h62e2ia58fr1tjbu8.apps.googleusercontent.com";

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: _webClientId,
    scopes: [
      drive.DriveApi.driveFileScope, // Access to files created by the app
    ],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  static const String _backupFileName = 'bazarhive_backup.zip';
  static const String _appFolderName = 'BazarHive';

  GoogleDriveService() {
    _googleSignIn.onCurrentUserChanged.listen((account) {
      _currentUser = account;
      if (_currentUser != null) {
        _initializeDriveApi();
      } else {
        _driveApi = null;
      }
    });
  }

  // Initialize Drive API
  Future<void> _initializeDriveApi() async {
    if (_currentUser == null) return;
    try {
      final authHeaders = await _currentUser!.authHeaders;
      final client = _GoogleAuthClient(authHeaders);
      _driveApi = drive.DriveApi(client);
    } catch (e) {
      debugPrint('Error initializing Drive API: $e');
      _driveApi = null;
    }
  }

  // Get current signed-in user
  GoogleSignInAccount? get currentUser => _currentUser;

  // Sign in
  Future<GoogleSignInAccount?> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser != null) {
        await _initializeDriveApi();
      }
      return _currentUser;
    } catch (e) {
      debugPrint('Error signing in: $e');
      return null;
    }
  }

  // Sign in silently
  Future<void> signInSilently() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        await _initializeDriveApi();
      }
    } catch (e) {
      debugPrint('Error signing in silently: $e');
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _googleSignIn.disconnect();
      _currentUser = null;
      _driveApi = null;
    } catch (e) {
      debugPrint('Error signing out: $e');
    }
  }

  // Helper to get or create the app folder
  Future<String?> _getOrCreateAppFolder() async {
    if (_driveApi == null) throw Exception('Drive API not initialized');

    try {
      // Check if folder exists
      final response = await _driveApi!.files.list(
        q: "mimeType='application/vnd.google-apps.folder' and name='$_appFolderName' and trashed=false",
        $fields: "files(id)",
      );

      if (response.files != null && response.files!.isNotEmpty) {
        return response.files!.first.id;
      } else {
        // Create folder if it doesn't exist
        final folder = drive.File()
          ..name = _appFolderName
          ..mimeType = 'application/vnd.google-apps.folder';
        final createdFolder = await _driveApi!.files.create(folder);
        return createdFolder.id;
      }
    } catch (e) {
      debugPrint('Error getting/creating app folder: $e');
      throw Exception('Failed to get or create app folder in Google Drive.');
    }
  }

  Future<Map<String, String>?> findLatestBackupDetails() async {
    if (_driveApi == null) throw Exception('Not signed in or Drive API not initialized.');

    try {
      final folderId = await _getOrCreateAppFolder();
      if (folderId == null) {
        debugPrint('Could not access the app folder in Google Drive.');
        return null;
      }

      final list = await _driveApi!.files.list(
          q: "name='$_backupFileName' and '$folderId' in parents and trashed=false",
          $fields: "files(id, name, modifiedTime)");

      if (list.files == null || list.files!.isEmpty) {
        debugPrint('No backup file found in Google Drive.');
        return null;
      }

      final backupFile = list.files!.first;
      return {
        'id': backupFile.id!,
        'name': backupFile.name!,
        'modifiedTime': backupFile.modifiedTime!.toIso8601String(),
      };
    } catch (e) {
      debugPrint('Error finding backup details: $e');
      throw Exception('Failed to find backup details from Google Drive.');
    }
  }

  // Upload backup
  Future<void> uploadBackup(String filePath) async {
    if (_driveApi == null) throw Exception('Not signed in or Drive API not initialized.');
    
    final file = File(filePath);
    if (!await file.exists()) throw Exception('Backup file not found at $filePath');

    try {
      final folderId = await _getOrCreateAppFolder();
      if (folderId == null) throw Exception('Could not access the app folder in Google Drive.');

      final driveFile = drive.File()
        ..name = _backupFileName
        ..parents = [folderId];

      // Check if file already exists to update it
      final list = await _driveApi!.files.list(
          q: "name='$_backupFileName' and '$folderId' in parents and trashed=false",
          $fields: "files(id)");

      final media = drive.Media(file.openRead(), await file.length());

      if (list.files != null && list.files!.isNotEmpty) {
        // Update existing file
        final fileId = list.files!.first.id!;
        await _driveApi!.files.update(drive.File(), fileId, uploadMedia: media);
        debugPrint('Backup updated successfully.');
      } else {
        // Create new file
        await _driveApi!.files.create(driveFile, uploadMedia: media);
        debugPrint('Backup created successfully.');
      }
      
      // Store last backup time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('google_drive_last_backup', DateTime.now().toIso8601String());

    } catch (e) {
      debugPrint('Error uploading backup: $e');
      throw Exception('Failed to upload backup to Google Drive.');
    }
  }

  // Download and restore backup
  Future<String?> downloadBackup() async {
    if (_driveApi == null) throw Exception('Not signed in or Drive API not initialized.');

    try {
      final folderId = await _getOrCreateAppFolder();
      if (folderId == null) throw Exception('Could not access the app folder in Google Drive.');

      final list = await _driveApi!.files.list(
          q: "name='$_backupFileName' and '$folderId' in parents and trashed=false",
          $fields: "files(id, name, modifiedTime)");
      
      if (list.files == null || list.files!.isEmpty) {
        debugPrint('No backup file found in Google Drive.');
        return null; // No backup found
      }

      final fileId = list.files!.first.id!;
      final media = await _driveApi!.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;

      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$_backupFileName';
      final file = File(filePath);

      final fileSink = file.openWrite();
      await media.stream.pipe(fileSink);
      await fileSink.close();

      debugPrint('Backup downloaded to $filePath');
      return filePath;

    } catch (e) {
      debugPrint('Error downloading backup: $e');
      throw Exception('Failed to download backup from Google Drive.');
    }
  }

  // Get last backup time
  Future<DateTime?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeString = prefs.getString('google_drive_last_backup');
    return timeString != null ? DateTime.parse(timeString) : null;
  }
}
