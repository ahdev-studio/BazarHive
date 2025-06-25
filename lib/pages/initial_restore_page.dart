import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import '../services/backup_service.dart';
import '../providers/google_drive_provider.dart';
import '../providers/theme_provider.dart';
import './onboarding_screen.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';

enum _RestoreStep {
  initial,
  signingIn,
  signedIn,
  searching,
  backupFound,
  backupNotFound,
  restoring,
  error
}

class InitialRestorePage extends StatefulWidget {
  const InitialRestorePage({super.key});

  @override
  State<InitialRestorePage> createState() => _InitialRestorePageState();
}

class _InitialRestorePageState extends State<InitialRestorePage> {
  _RestoreStep _currentStep = _RestoreStep.initial;
  bool _isLoading = false;
  String _errorMessage = '';
  String? _userName;
  Map<String, dynamic>? _backupInfo;
  double _restoreProgress = 0.0;
  String _restoreMessage = '';

  late final BackupService _backupService;
  late final GoogleDriveService _driveService;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // Initialization is now handled in didChangeDependencies to ensure context is available.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      final db = Provider.of<DatabaseHelper>(context, listen: false);
      final prefs = Provider.of<SharedPreferences>(context, listen: false);
      _backupService = BackupService(db, prefs);
      _driveService = Provider.of<GoogleDriveService>(context, listen: false);
      _checkSignInStatus();
      _isInitialized = true;
    }
  }

  Future<void> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        if (!mounted) return;
        final bool? userAgreed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
                'To restore backups from Google Drive or a local file, the app needs "All files access" to save the backup file temporarily. Please grant this permission in the next screen.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Open Settings')),
            ],
          ),
        );

        if (userAgreed == true) {
          status = await Permission.manageExternalStorage.request();
        }
      }
      if (!status.isGranted) {
        throw Exception('"All files access" is required to restore backup.');
      }
    }
  }

  Future<void> _restoreFromLocal() async {
    setState(() => _currentStep = _RestoreStep.restoring);
    try {
      await _requestStoragePermission();
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        await _backupService.restoreFromBackupFile(filePath, onProgress: (progress, message) {
          setState(() {
            _restoreProgress = progress;
            _restoreMessage = message;
          });
        });
        _showSuccessAndNavigate('Restore successful!');
      } else {
        setState(() => _currentStep = _RestoreStep.initial);
      }
    } catch (e) {
      _handleError(e.toString());
    }
  }

  Future<void> _checkSignInStatus() async {
    try {
      await _driveService.signInSilently();
      final user = _driveService.currentUser;
      if (user != null) {
        setState(() {
          _currentStep = _RestoreStep.signedIn;
          _userName = user.displayName;
        });
      }
    } catch (e) {
      debugPrint('Silent sign-in check failed: $e');
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _currentStep = _RestoreStep.signingIn;
      _isLoading = true;
    });
    try {
      final user = await _driveService.signIn();
      if (user != null) {
        setState(() {
          _currentStep = _RestoreStep.signedIn;
          _userName = user.displayName;
        });
      } else {
        // If user cancels sign-in, go back to the initial step
        setState(() {
          _currentStep = _RestoreStep.initial;
        });
      }
    } catch (e) {
      _handleError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _searchForBackup() async {
    setState(() => _currentStep = _RestoreStep.searching);
    try {
      final backupInfo = await _driveService.findLatestBackupDetails();
      if (backupInfo != null) {
        setState(() {
          _backupInfo = backupInfo;
          _currentStep = _RestoreStep.backupFound;
        });
      } else {
        setState(() => _currentStep = _RestoreStep.backupNotFound);
      }
    } catch (e) {
      _handleError(e.toString());
    }
  }

  Future<void> _restoreFromDrive() async {
    setState(() => _currentStep = _RestoreStep.restoring);
    try {
      if (_backupInfo == null) throw Exception('No backup file selected.');
      final downloadedPath = await _driveService.downloadBackup();
      if (downloadedPath == null) throw Exception('Failed to download backup file.');
      await _backupService.restoreFromBackupFile(downloadedPath, onProgress: (progress, message) {
        setState(() {
          _restoreProgress = progress;
          _restoreMessage = message;
        });
      });
      _showSuccessAndNavigate('Restore from Google Drive successful!');
    } catch (e) {
      _handleError(e.toString());
    }
  }

  void _skipRestore() {
    _navigateToOnboarding();
  }

  void _navigateToOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenInitialRestore', true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => OnboardingScreen(onComplete: () {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (Route<dynamic> route) => false);
      })),
      (Route<dynamic> route) => false,
    );
  }

  void _showSuccessAndNavigate(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green.shade700),
    );
    _navigateToOnboarding();
  }

  void _handleError(String error) {
    if (mounted) {
      setState(() {
        _errorMessage = error;
        _currentStep = _RestoreStep.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDarkMode
                ? const [Color(0xFF232526), Color(0xFF414345)]
                : const [Color(0xFF6DD5FA), Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHeader(),
                const SizedBox(height: 40),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      );
                    },
                    child: _buildCurrentStep(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGradientButton({
    required VoidCallback? onPressed,
    required Widget child,
    required List<Color> gradientColors,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        elevation: 5,
        shadowColor: Colors.black.withOpacity(0.2),
      ),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Container(
          width: double.infinity,
          height: 50,
          alignment: Alignment.center,
          child: _isLoading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : child,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: 60),
        Image.asset('assets/images/app_logo.png', height: 80),
        const SizedBox(height: 16),
        Text(
          'BazarHive',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 30,
          child: AnimatedTextKit(
            animatedTexts: [
              TyperAnimatedText(
                'Restore or Start Fresh',
                speed: const Duration(milliseconds: 100),
                textStyle: TextStyle(
                  fontSize: 18,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
            pause: const Duration(milliseconds: 1000),
            isRepeatingAnimation: true,
            repeatForever: true,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case _RestoreStep.initial:
        return _buildInitialStep();
      case _RestoreStep.signingIn:
        return _buildSigningInStep();
      case _RestoreStep.signedIn:
        return _buildSignedInStep();
      case _RestoreStep.searching:
        return _buildSearchingStep();
      case _RestoreStep.backupFound:
        return _buildBackupFoundStep();
      case _RestoreStep.backupNotFound:
        return _buildBackupNotFoundStep();
      case _RestoreStep.restoring:
        return _buildRestoringStep();
      case _RestoreStep.error:
        return _buildErrorStep();
    }
  }

  Widget _buildInitialStep() {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('initial'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF2980B9), Color(0xFF6DD5FA)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'Welcome Back!',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Restore your data to continue your journey.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: theme.colorScheme.secondary),
        ),
        const SizedBox(height: 40),
        _buildGradientButton(
          onPressed: _isLoading ? null : _signInWithGoogle,
          gradientColors: const [Color(0xFF007AFF), Color(0xFF00C6FF)],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/Drive.png', height: 24),
              const SizedBox(width: 12),
              const Text('Restore from Google Drive', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildGradientButton(
          onPressed: _isLoading ? null : _restoreFromLocal,
          gradientColors: const [Color(0xFF6B73FF), Color(0xFF000DFF)],
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.storage_outlined, color: Colors.white),
              SizedBox(width: 10),
              Text('Restore from Local Backup', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _isLoading ? null : _skipRestore,
          child: Text('Start Fresh', style: TextStyle(color: theme.colorScheme.primary)),
        ),
      ],
    );
  }

  Widget _buildLoadingStep(String key, String message) {
    final theme = Theme.of(context);
    return Column(
      key: ValueKey(key),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
        Text(message, style: TextStyle(fontSize: 16, color: theme.colorScheme.secondary)),
      ],
    );
  }

  Widget _buildSigningInStep() => _buildLoadingStep('signingIn', 'Signing in with Google...');

  Widget _buildSignedInStep() {
    return Column(
      key: const ValueKey('signedIn'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 40,
          backgroundImage: _driveService.currentUser?.photoUrl != null ? NetworkImage(_driveService.currentUser!.photoUrl!) : null,
          child: _driveService.currentUser?.photoUrl == null ? const Icon(Icons.person, size: 40) : null,
        ),
        const SizedBox(height: 16),
        Text(
          'Signed In as ${_userName ?? '...'}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(_driveService.currentUser?.email ?? '', style: const TextStyle(fontSize: 16, color: Colors.black54)),
        const SizedBox(height: 30),
        _buildGradientButton(
          onPressed: _searchForBackup,
          gradientColors: const [Color(0xFF007AFF), Color(0xFF00C6FF)],
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_queue, color: Colors.white),
              SizedBox(width: 10),
              Text('Search for Backup', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _currentStep = _RestoreStep.initial),
          child: const Text('Use a different account'),
        )
      ],
    );
  }

  Widget _buildSearchingStep() => _buildLoadingStep('searching', 'Searching for backups on Google Drive...');

  Widget _buildBackupFoundStep() {
    final modifiedTime = DateTime.parse(_backupInfo!['modifiedTime']);
    final formattedDate = DateFormat('d MMMM yyyy, hh:mm a').format(modifiedTime);
    return Column(
      key: const ValueKey('backupFound'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.cloud_done, size: 80, color: Colors.greenAccent),
        const SizedBox(height: 16),
        const Text('Backup Found!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Last backup: $formattedDate',
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 30),
        _buildGradientButton(
          onPressed: _restoreFromDrive,
          gradientColors: const [Color(0xFF11998e), Color(0xFF38ef7d)],
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restore, color: Colors.white),
              SizedBox(width: 10),
              Text('Restore Now', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _skipRestore,
          child: const Text('Start Fresh Instead'),
        ),
      ],
    );
  }

  Widget _buildBackupNotFoundStep() {
    return Column(
      key: const ValueKey('backupNotFound'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.cloud_off, size: 80, color: Colors.orange.shade600),
        const SizedBox(height: 16),
        const Text('No Backup Found', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'We couldn\'t find any backup file in your Google Drive.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 30),
        _buildGradientButton(
          onPressed: _skipRestore,
          gradientColors: const [Color(0xFF007AFF), Color(0xFF00C6FF)],
          child: const Text('Start Fresh', style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildRestoringStep() {
    return Column(
      key: const ValueKey('restoring'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _restoreMessage,
          style: const TextStyle(fontSize: 18),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        LinearProgressIndicator(
          value: _restoreProgress,
          minHeight: 10,
          backgroundColor: Colors.grey.shade300,
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
        ),
        const SizedBox(height: 10),
        Text('${(_restoreProgress * 100).toStringAsFixed(0)}%'),
      ],
    );
  }

  Widget _buildErrorStep() {
    return Column(
      key: const ValueKey('error'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 80, color: Colors.red.shade600),
        const SizedBox(height: 16),
        const Text('An Error Occurred', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          _errorMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 30),
        _buildGradientButton(
          onPressed: () => setState(() => _currentStep = _RestoreStep.initial),
          gradientColors: const [Color(0xFFF7971E), Color(0xFFFFD200)],
          child: const Text('Try Again', style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
      ],
    );
  }
}
