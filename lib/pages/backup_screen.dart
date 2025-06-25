import 'dart:io';
import 'package:BazarHive/widgets/banner_ad_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:io' show Platform;
import 'package:file_picker/file_picker.dart';
import 'package:BazarHive/database/database_helper.dart';
import 'package:BazarHive/services/backup_service.dart';
import 'package:BazarHive/providers/google_drive_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> with WidgetsBindingObserver, RouteAware {
  static const platform = MethodChannel('com.bazarhive/battery');

  int _backupFrequencyInDays = 1;
  bool _isAutoBackupEnabled = false;
  TimeOfDay _backupTime = const TimeOfDay(hour: 2, minute: 0); // Default time 2:00 AM
  late BackupService _backupService;
  late GoogleDriveService _driveService;
  bool _isLoading = false;
  String? _lastLocalBackup;
  String? _lastGoogleDriveBackup;
  GoogleSignInAccount? _currentUser;

  bool _isSigningIn = false;

  bool _isRestoring = false;
  double _restoreProgress = 0.0;
  String _restoreMessage = '';
  String _activeRestoreType = ''; // 'local' or 'drive'

  bool _isBackingUp = false;
  String _activeBackupType = ''; // 'local' or 'drive'
  double _backupProgress = 0.0;
  String _backupMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices().then((_) {
      _checkCurrentUser();
      _loadLastBackupDetails();
      _loadPreferences();
    });

  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadLastBackupDetails();
    }
  }



  Future<void> _initializeServices() async {
    final prefs = await SharedPreferences.getInstance();
    final dbHelper = DatabaseHelper();
    _backupService = BackupService(dbHelper, prefs);
    _driveService = GoogleDriveService();
  }

  Future<void> _loadLastBackupDetails() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Force reload to get latest data from background isolate
    if (mounted) {
      setState(() {
        _lastLocalBackup = prefs.getString('lastLocalBackup');
        _lastGoogleDriveBackup = prefs.getString('lastGoogleDriveBackup');
      });
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isAutoBackupEnabled = prefs.getBool('autoBackupEnabled') ?? false;
        _backupFrequencyInDays = prefs.getInt('backupFrequency') ?? 1;
        final hour = prefs.getInt('backupHour') ?? 2;
        final minute = prefs.getInt('backupMinute') ?? 0;
        _backupTime = TimeOfDay(hour: hour, minute: minute);
      });
    }
  }

  Future<void> _checkCurrentUser() async {
    await _driveService.signInSilently();
    if (mounted) {
      setState(() {
        _currentUser = _driveService.currentUser;
      });
    }
  }

  Future<void> _handleSignIn() async {
    setState(() => _isSigningIn = true);
    try {
      await Workmanager().registerOneOffTask(
        "local_backup_task_${DateTime.now().millisecondsSinceEpoch}",
        "local_backup",
        inputData: <String, dynamic>{'backup_type': 'local'},
      );

      await _driveService.signIn();
      if (mounted) {
        setState(() {
          _currentUser = _driveService.currentUser;
        });
      }
    } catch (error) {
      if (kDebugMode) {
        print('Sign in error: $error');
      }
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-in failed: $error')),
        );
      }
    } finally {
      if(mounted){
        setState(() => _isSigningIn = false);
      }
    }
  }

  Future<void> _handleSignOut() async {
    await _driveService.signOut();
    if(mounted){
      setState(() {
        _currentUser = null;
      });
    }
  }

  String _formatDateTime(String iso8601String) {
    final dateTime = DateTime.parse(iso8601String);
    return DateFormat('d MMMM yyyy, hh:mm a').format(dateTime);
  }

  Future<bool> _requestBatteryOptimizationPermission() async {
    if (!Platform.isAndroid) return true;

    // Check if battery optimization is already disabled via native code
    final bool isIgnoring = await platform.invokeMethod('isIgnoringBatteryOptimizations');
    if (isIgnoring) return true;

    if (!mounted) return false;

    // Show a dialog to the user
    final bool? userAgreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reliable Backups'),
        content: const Text('To ensure automatic backups run on schedule, please disable battery optimization for BazarHive. This prevents the system from stopping the backup process to save power.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('CANCEL')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('ALLOW')),
        ],
      ),
    );

    // If user agreed, request to disable optimization via native code
    if (userAgreed == true) {
      await platform.invokeMethod('openBatteryOptimizationSettings');
      // We can't know for sure if the user enabled it, but we opened the settings.
      // We will assume they did for a better user experience. The check will run again next time.
      return true;
    }
    
    return false;
  }

  void _handleAutoBackupToggle(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    if (!value) {
      // Turn OFF logic
      await Workmanager().cancelByUniqueName("auto_backup_task");
      await prefs.setBool('autoBackupEnabled', false);
      if (mounted) setState(() => _isAutoBackupEnabled = false);
      return;
    }

    // --- Turn ON Logic ---
    if (_currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Please sign in to Google Drive to enable automatic backups.')),
        );
      }
      return;
    }

    final hasPermissions = await _checkAndRequestPermissions();
    if (!hasPermissions && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Storage permissions are required for automatic backups.')),
      );
      setState(() => _isAutoBackupEnabled = false);
      await prefs.setBool('autoBackupEnabled', false);
      return;
    }

    // Check for "Ignore Battery Optimizations" permission
    bool batteryPermissionGranted = true; // Assume granted
    if (Platform.isAndroid) {
      batteryPermissionGranted =
          await Permission.ignoreBatteryOptimizations.isGranted;
      if (!batteryPermissionGranted) {
        final bool? userWantsToAllow = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
                'To ensure automatic backups run reliably, please disable battery optimization for BazarHive.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Later')),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Allow')),
            ],
          ),
        );

        if (userWantsToAllow == true) {
          await Permission.ignoreBatteryOptimizations.request();
          batteryPermissionGranted =
              await Permission.ignoreBatteryOptimizations.isGranted;
        }
      }
    }

    // --- Final Decision ---
    if (hasPermissions && batteryPermissionGranted) {
      if (mounted) setState(() => _isAutoBackupEnabled = true);
      await prefs.setBool('autoBackupEnabled', true);
      await _scheduleAutoBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Automatic backup enabled.')),
        );
      }
    } else {
      if (mounted) setState(() => _isAutoBackupEnabled = false);
      await prefs.setBool('autoBackupEnabled', false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Automatic backup not enabled due to missing permissions.')),
        );
      }
    }
  }





  Future<void> _pickBackupTime() async {
    final newTime = await showTimePicker(
      context: context,
      initialTime: _backupTime,
    );
    if (newTime != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('backupHour', newTime.hour);
      await prefs.setInt('backupMinute', newTime.minute);
      setState(() {
        _backupTime = newTime;
      });
      if (_isAutoBackupEnabled) {
        await _scheduleAutoBackup(); // Reschedule with new time
      }
    }
  }

  Future<void> _scheduleAutoBackup() async {
    if (!_isAutoBackupEnabled) return;

    if (kDebugMode) {
      print('Scheduling auto backup...');
    }
    await Workmanager().registerPeriodicTask(
      'auto_backup_task',
      'auto_backup_task',
      frequency: Duration(days: _backupFrequencyInDays),
      initialDelay: _calculateInitialDelay(),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      inputData: <String, dynamic>{'backup_type': 'drive'},
    );
  }

  void _updateBackupFrequency(int? newFrequency) async {
    if (newFrequency != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('backupFrequency', newFrequency);
      setState(() {
        _backupFrequencyInDays = newFrequency;
      });
      if (_isAutoBackupEnabled) {
        await _scheduleAutoBackup(); // Reschedule with new frequency
      }
    }
  }

  Future<void> _runBackupNow() async {
    if (kDebugMode) {
      print('Running a test backup in 5 seconds...');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test backup will start in 5 seconds.')),
    );
    await Workmanager().registerOneOffTask(
      'auto_backup_test_task_one_off',
      'auto_backup_task',
      initialDelay: const Duration(seconds: 5),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      inputData: <String, dynamic>{'backup_type': 'drive'},
    );
  }

  Duration _calculateInitialDelay() {
    final now = DateTime.now();
    var scheduledTime = DateTime(now.year, now.month, now.day, _backupTime.hour, _backupTime.minute);
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }
    return scheduledTime.difference(now);
  }



  Future<bool> _checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      PermissionStatus status;
      // For Android 11 (SDK 30) and above, MANAGE_EXTERNAL_STORAGE is needed for broad file access.
      if (deviceInfo.version.sdkInt >= 30) {
        status = await Permission.manageExternalStorage.request();
      } else {
      // For older versions, storage permission is sufficient.
        status = await Permission.storage.request();
      }

      if (status.isPermanentlyDenied) {
        // Guide user to app settings if permission is permanently denied.
        await openAppSettings();
      }
      
      return status.isGranted;
    }
    return true; // Assume permission is granted for non-Android platforms.
  }

  Future<void> _createLocalBackup() async {
    final confirmed = await _showBackupConfirmationDialog();
    if (!confirmed || !mounted) return;

    if (!await _checkAndRequestPermissions()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission is required.')),
        );
      }
      return;
    }

    setState(() {
      _isBackingUp = true;
      _activeBackupType = 'local';
      _backupProgress = 0.0;
      _backupMessage = 'Starting local backup...';
    });

    try {
      final tempPath = await _backupService.createBackupFile(onProgress: (progress, message) {
        if (mounted) {
          setState(() {
            _backupProgress = progress;
            _backupMessage = message;
          });
        }
      });

      if (tempPath == null) {
        throw Exception('Failed to create temporary backup file.');
      }

      final publicPath = await _backupService.saveBackupFileToPublicLocation(tempPath);
      await File(tempPath).delete(); // Clean up temp file

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastLocalBackup', DateTime.now().toIso8601String());

      // Create signal file to notify UI to reload timestamps
      final directory = await getApplicationDocumentsDirectory();
      final signalFile = File(path.join(directory.path, 'backup.signal'));
      await signalFile.create(recursive: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Local backup saved to: ${path.basename(publicPath)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Local backup failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
          _activeBackupType = '';
        });
      }
    }
  }

  void _showPermissionDeniedDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
            'Storage permission is required to perform this action. Please enable it in the app settings.'),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text('Open Settings'),
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _restoreFromLocalBackup() async {
    if (!await _checkAndRequestPermissions()) {
      _showPermissionDeniedDialog();
      return;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any, // Allow any file to be picked to ensure visibility
    );

    if (result == null || result.files.single.path == null) {
      return; // User canceled picker
    }

    final confirmed = await _showRestoreConfirmationDialog();
    if (!confirmed || !mounted) return;

    setState(() {
      _isRestoring = true;
      _activeRestoreType = 'local';
      _restoreProgress = 0.0;
      _restoreMessage = 'Starting restore...';
    });

    try {
      await _backupService.restoreFromBackupFile(
        result.files.single.path!,
        onProgress: (progress, message) {
          if (mounted) {
            setState(() {
              _restoreProgress = progress;
              _restoreMessage = message;
            });
          }
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data restored successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
          _activeRestoreType = '';
        });
      }
    }
  }

  Future<void> _createGoogleDriveBackup() async {
    final confirmed = await _showBackupConfirmationDialog();
    if (!confirmed || !mounted) return;

    setState(() {
      _isBackingUp = true;
      _activeBackupType = 'drive';
      _backupProgress = 0.0;
      _backupMessage = 'Starting Google Drive backup...';
    });

    try {
      // First, create a temporary local backup file
      final tempPath = await _backupService.createBackupFile(onProgress: (progress, message) {
        if (mounted) {
          setState(() {
            _backupProgress = progress * 0.5; // 50% for local backup
            _backupMessage = message;
          });
        }
      });

      if (tempPath == null) {
        throw Exception('Failed to create temporary backup file.');
      }

      // Then, upload it to Google Drive
      setState(() {
        _backupProgress = 0.5;
        _backupMessage = 'Uploading to Google Drive...';
      });
      await _driveService.uploadBackup(tempPath);

      // Clean up temporary file
      await File(tempPath).delete();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastGoogleDriveBackup', DateTime.now().toIso8601String());

      // Create signal file to notify UI to reload timestamps
      final directory = await getApplicationDocumentsDirectory();
      final signalFile = File(path.join(directory.path, 'backup.signal'));
      await signalFile.create(recursive: true);

      setState(() {
        _backupProgress = 1.0;
        _backupMessage = 'Upload complete!';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google Drive backup successful!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Drive backup failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
          _activeBackupType = '';
        });
      }
    }
  }

  Future<void> _restoreFromGoogleDrive() async {
    final confirmed = await _showRestoreConfirmationDialog();
    if (!confirmed || !mounted) return;

    setState(() {
      _isRestoring = true;
      _activeRestoreType = 'drive';
      _restoreProgress = 0.0;
      _restoreMessage = 'Downloading from Google Drive...';
    });

    try {
      // First, download the backup file from Google Drive
      final downloadedPath = await _driveService.downloadBackup();

      if (downloadedPath == null) {
        throw Exception('No backup file found in Google Drive.');
      }

      // Then, restore from the downloaded file
      setState(() {
        _restoreMessage = 'Restoring data...';
      });
      await _backupService.restoreFromBackupFile(
        downloadedPath,
        onProgress: (progress, message) {
          if (mounted) {
            setState(() {
              _restoreProgress = progress;
              _restoreMessage = message;
            });
          }
        },
      );

      // Clean up downloaded file
      await File(downloadedPath).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data restored successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore from Google Drive failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
          _activeRestoreType = '';
        });
      }
    }
  }

  Future<bool> _showBackupConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Backup'),
        content: const Text('A new backup file will be created. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Backup')),
        ],
      ),
    ) ?? false;
  }

  Future<bool> _showRestoreConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Restore'),
        content: const Text('This will overwrite all current data. This action cannot be undone. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Restore')),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.colorScheme.surface;
    final onCardColor = theme.colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Backup & Restore'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildAutoBackupCard(cardColor, onCardColor),
              const SizedBox(height: 16),
              _buildGoogleDriveCard(cardColor, onCardColor),
              const SizedBox(height: 16),
              _buildLocalBackupCard(cardColor, onCardColor),
              const SizedBox(height: 60), // Space for banner ad
            ],
          ),
          // Global progress indicator for sign-in, as it's not tied to a card
          if (_isSigningIn)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Signing in...'),
                        SizedBox(height: 20),
                        CircularProgressIndicator(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: BannerAdWidget(),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoBackupCard(Color cardColor, Color onCardColor) {
    return Card(
      elevation: 2,
      color: cardColor,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Auto Backup Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: onCardColor)),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text('Enable Auto Backup', style: TextStyle(color: onCardColor)),
              value: _isAutoBackupEnabled,
              onChanged: _isLoading || _currentUser == null ? null : _handleAutoBackupToggle,
              secondary: Icon(Icons.sync_rounded, color: onCardColor.withOpacity(0.8)),
            ),
            if (_isAutoBackupEnabled && _currentUser != null) ...[
              const Divider(),
              ListTile(
                leading: Icon(Icons.calendar_today_rounded, color: onCardColor.withOpacity(0.8)),
                title: Text('Backup Frequency', style: TextStyle(color: onCardColor)),
                trailing: DropdownButton<int>(
                  value: _backupFrequencyInDays,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Daily')),
                    DropdownMenuItem(value: 7, child: Text('Weekly')),
                    DropdownMenuItem(value: 30, child: Text('Monthly')),
                  ],
                  onChanged: _updateBackupFrequency,
                ),
              ),
              ListTile(
                leading: Icon(Icons.access_time_rounded, color: onCardColor.withOpacity(0.8)),
                title: Text('Backup Time', style: TextStyle(color: onCardColor)),
                trailing: TextButton(
                  child: Text(_backupTime.format(context)),
                  onPressed: _pickBackupTime,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: OutlinedButton.icon(
                  onPressed: _runBackupNow,
                  icon: const Icon(Icons.backup_rounded),
                  label: const Text('Run Backup Now'),
                ),
              )
            ],
            if (_currentUser == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Please sign in with Google to enable auto backup.',
                  style: TextStyle(color: onCardColor.withOpacity(0.7)),
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleDriveCard(Color cardColor, Color onCardColor) {
    final bool isThisCardWorking = (_isBackingUp && _activeBackupType == 'drive') || (_isRestoring && _activeRestoreType == 'drive');

    return Card(
      elevation: 2,
      color: cardColor,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset('assets/images/Drive.png', height: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Text('Google Drive Backup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: onCardColor)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Securely back up your data to your Google account.', style: TextStyle(color: onCardColor.withOpacity(0.7))),
            const SizedBox(height: 16),
            if (_currentUser != null) ...[
              // Logged-in view
              Row(
                children: [
                  GoogleUserCircleAvatar(identity: _currentUser!),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_currentUser!.displayName ?? 'No Name', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(_currentUser!.email, style: TextStyle(color: onCardColor.withOpacity(0.7))),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.logout), onPressed: _handleSignOut, tooltip: 'Sign Out'),
                ],
              ),
              const SizedBox(height: 16),
              if (_lastGoogleDriveBackup != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text('Last backup: ${_formatDateTime(_lastGoogleDriveBackup!)}', style: TextStyle(color: onCardColor.withOpacity(0.7))),
                ),
              if (isThisCardWorking)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    children: [
                      LinearProgressIndicator(value: _isBackingUp ? _backupProgress : _restoreProgress),
                      const SizedBox(height: 8),
                      Text(_isBackingUp ? _backupMessage : _restoreMessage),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isBackingUp || _isRestoring ? null : _createGoogleDriveBackup,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('Backup'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isBackingUp || _isRestoring ? null : _restoreFromGoogleDrive,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('Restore'),
                      ),
                    ),
                  ],
                ),
            ] else ...[
              // Logged-out view
              Center(
                child: _isSigningIn
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        onPressed: _handleSignIn,
                        icon: Image.asset('assets/images/google_logo.png', height: 24),
                        label: const Text('Sign in with Google'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildLocalBackupCard(Color cardColor, Color onCardColor) {
    final bool isThisCardWorking = (_isBackingUp && _activeBackupType == 'local') || (_isRestoring && _activeRestoreType == 'local');

    return Card(
      elevation: 2,
      color: cardColor,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage_rounded, size: 40, color: onCardColor.withOpacity(0.8)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text('Local Device Backup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: onCardColor)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Save a backup to your device. Useful for manual transfers.', style: TextStyle(color: onCardColor.withOpacity(0.7))),
            const SizedBox(height: 16),
            if (_lastLocalBackup != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text('Last backup: ${_formatDateTime(_lastLocalBackup!)}', style: TextStyle(color: onCardColor.withOpacity(0.7))),
              ),
            if (isThisCardWorking)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  children: [
                    LinearProgressIndicator(value: _isBackingUp ? _backupProgress : _restoreProgress),
                    const SizedBox(height: 8),
                    Text(_isBackingUp ? _backupMessage : _restoreMessage),
                  ],
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isBackingUp || _isRestoring ? null : _createLocalBackup,
                      icon: const Icon(Icons.save_alt_outlined),
                      label: const Text('Backup'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isBackingUp || _isRestoring ? null : _restoreFromLocalBackup,
                      icon: const Icon(Icons.restore_outlined),
                      label: const Text('Restore'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
