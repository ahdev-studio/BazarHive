import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pinput/pinput.dart';
import 'dart:math' show sin, pi;
import '../providers/security_provider.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const LockScreen({
    super.key,
    required this.onUnlocked,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  String _errorMessage = '';
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkBiometric();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  Future<void> _authenticateWithBiometrics() async {
    final securityProvider = Provider.of<SecurityProvider>(context, listen: false);
    if (securityProvider.isBiometricEnabled) {
      setState(() => _isAuthenticating = true);
      final success = await securityProvider.authenticateWithBiometrics();
      if (success && mounted) {
        widget.onUnlocked();
      }
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    }
  }

  Future<void> _checkBiometric() async {
    final securityProvider = Provider.of<SecurityProvider>(context, listen: false);
    if (securityProvider.isBiometricEnabled) {
      setState(() => _isAuthenticating = true);
      final authenticated = await securityProvider.authenticateWithBiometrics();
      if (mounted) {
        setState(() => _isAuthenticating = false);
        if (authenticated) {
          widget.onUnlocked();
        }
      }
    }
  }

  Future<void> _verifyPin() async {
    if (_pinController.text.length != 4) {
      setState(() => _errorMessage = 'Please enter 4 digits');
      return;
    }

    final securityProvider = Provider.of<SecurityProvider>(context, listen: false);
    final isValid = await securityProvider.verifyPin(_pinController.text);

    if (mounted) {
      if (isValid) {
        widget.onUnlocked();
      } else {
        setState(() => _errorMessage = 'Invalid PIN');
        _pinController.clear();
        _shakeController.forward(from: 0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 56,
      height: 56,
      textStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.7)),
      ),
    );
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF388E3C),  // Light green
              Colors.grey.shade200,     // Light grey at the bottom
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/app_logo.png',
                      width: 120,
                      height: 120,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'BazarHive',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onBackground,
                          ),
                    ),
                    const SizedBox(height: 48),
                    Text(
                      'Enter your PIN',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onBackground.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedBuilder(
                      animation: _shakeController,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(
                            sin(_shakeController.value * 4 * pi) * 10,
                            0,
                          ),
                          child: child,
                        );
                      },
                      child: Pinput(
                        controller: _pinController,
                        focusNode: _pinFocusNode,
                        autofocus: true,
                        length: 4,
                        defaultPinTheme: defaultPinTheme,
                        focusedPinTheme: defaultPinTheme.copyWith(
                          decoration: defaultPinTheme.decoration?.copyWith(
                            border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                          ),
                        ),
                        obscureText: true,
                        onCompleted: (_) => _verifyPin(),
                        onChanged: (_) {
                          if (_errorMessage.isNotEmpty) {
                            setState(() => _errorMessage = '');
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_errorMessage.isNotEmpty)
                      Text(
                        _errorMessage,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(height: 24),
                    Consumer<SecurityProvider>(
                      builder: (context, securityProvider, _) {
                        if (!securityProvider.isBiometricEnabled) {
                          return const SizedBox.shrink();
                        }
                        return IconButton(
                          icon: _isAuthenticating
                              ? CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)
                              : Icon(Icons.fingerprint, color: Theme.of(context).colorScheme.primary, size: 48),
                          onPressed: _isAuthenticating ? null : _checkBiometric,
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
