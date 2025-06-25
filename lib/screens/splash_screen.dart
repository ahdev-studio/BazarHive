import 'package:flutter/material.dart';
import '../pages/initial_restore_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/security_provider.dart';
import '../widgets/terms_dialog_bazarhive.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );

    _animationController.forward();

    // Navigate after splash animation
    Future.delayed(const Duration(milliseconds: 2500), () async {
      if (mounted) {
        try {
          // Check for app lock first
          final securityProvider = Provider.of<SecurityProvider>(context, listen: false);
          if (securityProvider.isAppLockEnabled) {
            // If lock is enabled, go to lock screen and stop further navigation here.
            debugPrint('SplashScreen: App lock enabled, navigating to /lock');
            Navigator.pushReplacementNamed(context, '/lock');
            return;
          }

          final prefs = await SharedPreferences.getInstance();
          final bool initialRestoreOffered = prefs.getBool('initial_restore_offered') ?? false;

          if (!initialRestoreOffered) {
            debugPrint('SplashScreen: Navigating to /initial_restore');
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const InitialRestorePage()));
          } else {
            final bool onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;

            debugPrint('SplashScreen: onboardingCompleted = $onboardingCompleted');

            // Check if terms should be shown first
            final shouldShowTerms = await TermsDialogBazarHive.shouldShowTerms();

            if (shouldShowTerms) {
              debugPrint('SplashScreen: Showing terms dialog');
              final result = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) => const TermsDialogBazarHive(),
              );

              // If terms declined, app will exit via dialog
              // If terms accepted, continue with normal flow
              if (result == true && mounted) {
                if (onboardingCompleted) {
                  debugPrint('SplashScreen: Terms accepted, navigating to /home');
                  Navigator.pushReplacementNamed(context, '/home');
                } else {
                  debugPrint('SplashScreen: Terms accepted, navigating to /onboarding');
                  Navigator.pushReplacementNamed(context, '/onboarding');
                }
              }
            } else {
              // Terms already accepted, proceed with normal flow
              if (onboardingCompleted) {
                debugPrint('SplashScreen: Navigating to /home');
                Navigator.pushReplacementNamed(context, '/home');
              } else {
                debugPrint('SplashScreen: Navigating to /onboarding');
                Navigator.pushReplacementNamed(context, '/onboarding');
              }
            }
          }
        } catch (e) {
          debugPrint('SplashScreen: Error in navigation flow: $e');
          // Fallback to home if there's an error
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              // Logo
              FadeTransition(
                opacity: _fadeAnimation,
                child: Image.asset(
                  'assets/images/app_logo.png',
                  width: 150,
                  height: 150,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),
              // App Name
              FadeTransition(
                opacity: _fadeAnimation,
                child: Text(
                  'BazarHive',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onBackground,
                      ),
                ),
              ),
              const SizedBox(height: 16),
              // Tagline
              FadeTransition(
                opacity: _fadeAnimation,
                child: Text(
                  'Smart Bazar Manager',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onBackground.withOpacity(0.8),
                      ),
                ),
              ),
              const Spacer(),
              // Loading indicator
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
