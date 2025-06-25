import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:BazarHive/database/database_helper.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class BackupService {
  final DatabaseHelper _dbHelper;
  final SharedPreferences _prefs;

  BackupService(this._dbHelper, this._prefs);

  Future<String?> createBackupFile(
      {required Function(double progress, String message) onProgress}) async {
    onProgress(0.0, 'Starting backup...');

    final archive = Archive();

    onProgress(0.1, 'Backing up database...');
    await _dbHelper.closeDatabase();
    final dbPath = await _dbHelper.getDbPath();
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      archive.addFile(ArchiveFile(
          'database.db', dbFile.lengthSync(), await dbFile.readAsBytes()));
    }

    onProgress(0.3, 'Backing up settings and images...');
    final allPrefs = <String, dynamic>{};
    final allImagePaths = <String>[];

    allImagePaths.addAll(await _dbHelper.getAllImagePaths());

    for (String key in _prefs.getKeys()) {
      final value = _prefs.get(key);
      allPrefs[key] = value;
      if (key == 'profile_picture' && value is String && value.isNotEmpty) {
        allImagePaths.add(value);
      }
    }
    final prefsString = jsonEncode(allPrefs);
    archive.addFile(ArchiveFile(
        'preferences.json', prefsString.length, utf8.encode(prefsString)));

    onProgress(0.6, 'Archiving images...');
    final uniqueImagePaths = allImagePaths.toSet().toList();
    if (uniqueImagePaths.isNotEmpty) {
      for (int i = 0; i < uniqueImagePaths.length; i++) {
        final imagePath = uniqueImagePaths[i];
        final imageFile = File(imagePath);
        if (await imageFile.exists()) {
          archive.addFile(ArchiveFile(
            imagePath,
            imageFile.lengthSync(),
            await imageFile.readAsBytes(),
          ));
        }
        onProgress(
            0.6 + (0.3 * ((i + 1) / uniqueImagePaths.length)),
            'Archiving image ${i + 1} of ${uniqueImagePaths.length}');
      }
    }

    onProgress(0.9, 'Saving temporary backup file...');
    final zipEncoder = ZipEncoder();
    final zipData = zipEncoder.encode(archive);
    if (zipData == null) {
      throw Exception('Failed to create ZIP file.');
    }

    final tempDir = await getTemporaryDirectory();
    final fileName =
        'BazarHive_Backup_Temp_${DateTime.now().millisecondsSinceEpoch}.zip';
    final backupFilePath = path.join(tempDir.path, fileName);
    final backupFile = File(backupFilePath);
    await backupFile.writeAsBytes(zipData);

    onProgress(1.0, 'Temporary backup created.');
    return backupFilePath;
  }



  Future<void> restoreFromBackupFile(String backupFilePath,
      {required Function(double progress, String message) onProgress}) async {
    onProgress(0.0, 'Starting restore...');
    final backupFile = File(backupFilePath);
    if (!await backupFile.exists()) {
      throw Exception('Backup file not found at $backupFilePath');
    }

    onProgress(0.1, 'Reading backup file...');
    final archive = ZipDecoder().decodeBytes(await backupFile.readAsBytes());

    onProgress(0.2, 'Closing database...');
    await _dbHelper.closeDatabase();

    onProgress(0.3, 'Restoring files...');
    for (final file in archive) {
      final filePath = file.name;
      final fileData = file.content as List<int>;

      if (filePath == 'database.db') {
        onProgress(0.4, 'Restoring database...');
        final dbPath = await _dbHelper.getDbPath();
        await File(dbPath).writeAsBytes(fileData);
      } else if (filePath == 'preferences.json') {
        onProgress(0.6, 'Restoring settings...');
        await _prefs.clear();
        final prefsString = utf8.decode(fileData);
        final allPrefs = jsonDecode(prefsString) as Map<String, dynamic>;
        for (String key in allPrefs.keys) {
          dynamic value = allPrefs[key];
          if (value is bool)
            await _prefs.setBool(key, value);
          else if (value is int)
            await _prefs.setInt(key, value);
          else if (value is double)
            await _prefs.setDouble(key, value);
          else if (value is String)
            await _prefs.setString(key, value);
          else if (value is List)
            await _prefs.setStringList(key, value.cast<String>());
        }
      } else if (path.isAbsolute(filePath)) {
        onProgress(0.8, 'Restoring image: ${path.basename(filePath)}');
        final imageFile = File(filePath);
        final parentDir = imageFile.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
        await imageFile.writeAsBytes(fileData);
      }
    }
    onProgress(1.0, 'Restore process complete!');
  }

  Future<String> saveBackupFileToPublicLocation(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source file does not exist: $sourcePath');
    }

    Directory? downloadsDir;
    if (Platform.isAndroid) {
      // This is a common way to get the public downloads directory.
      Directory? externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        throw Exception('Could not access external storage.');
      }
      // Path construction to get to the root of the external storage.
      String rootPath = externalDir.path.split('/Android/data').first;
      downloadsDir = Directory(path.join(rootPath, 'Download'));
    } else {
      // Fallback for iOS/other platforms
      downloadsDir = await getApplicationDocumentsDirectory();
    }

    // Now construct the custom path as requested by the user
    final customDirPath = path.join(downloadsDir.path, 'BazarHive by AHDS', 'Database');
    final customDir = Directory(customDirPath);

    // Create the directory if it doesn't exist
    if (!await customDir.exists()) {
      await customDir.create(recursive: true);
    }

    // Use the fixed filename as requested by the user
    final fileName = 'BazarHive backup by AHDS.zip';
    final destinationPath = path.join(customDir.path, fileName);
    
    // Copy the file, which will overwrite if it already exists.
    await sourceFile.copy(destinationPath);
    
    return destinationPath;
  }
}
