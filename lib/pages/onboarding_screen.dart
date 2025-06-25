import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/theme_provider.dart';
import '../providers/currency_provider.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'dart:math' as math;
import '../providers/security_provider.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({
    Key? key,
    required this.onComplete,
  }) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}


class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLastPage = false;
  bool _showIntro = true;
  final TextEditingController _pinController = TextEditingController();
  String _errorMessage = '';
  List<dynamic> _filteredCurrencies = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currencyProvider = Provider.of<CurrencyProvider>(context, listen: false);
      setState(() {
        _filteredCurrencies = currencyProvider.currencies;
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pinController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    await prefs.setBool('initial_restore_offered', true); // Ensure this is also set
    widget.onComplete();
  }

  Widget _buildCurrencyPage(CurrencyProvider currencyProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.currency_exchange,
            size: 80,
            color: Colors.green,
          ),
          const SizedBox(height: 24),
          const Text(
            'Select Your Currency',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Choose the currency you want to use for your shopping lists',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search currency...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (String value) {
              setState(() {
                _filteredCurrencies = currencyProvider.currencies
                    .where((currency) =>
                        currency.name.toLowerCase().contains(value.toLowerCase()) ||
                        currency.symbol.toLowerCase().contains(value.toLowerCase()))
                    .toList();
              });
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filteredCurrencies.length,
              itemBuilder: (BuildContext context, int index) {
                final currency = _filteredCurrencies[index];
                return RadioListTile<String>(
                  title: Text('${currency.symbol} ${currency.name}'),
                  value: currency.symbol,
                  groupValue: currencyProvider.selectedCurrencySymbol,
                  onChanged: (String? value) async {
                    if (value != null) {
                      await currencyProvider.setSelectedCurrency(value);
                      setState(() {});
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemePage(ThemeProvider themeProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.palette_outlined,
            size: 80,
            color: Colors.blue,
          ),
          const SizedBox(height: 24),
          const Text(
            'Choose Your Theme',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Select a theme that suits your style',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 32),
          _buildThemeOption(
            context,
            'Light',
            Icons.light_mode,
            ThemeMode.light,
            themeProvider,
          ),
          const SizedBox(height: 16),
          _buildThemeOption(
            context,
            'Dark',
            Icons.dark_mode,
            ThemeMode.dark,
            themeProvider,
          ),
          const SizedBox(height: 16),
          _buildThemeOption(
            context,
            'System Default',
            Icons.settings_system_daydream,
            ThemeMode.system,
            themeProvider,
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    String label,
    IconData icon,
    ThemeMode mode,
    ThemeProvider themeProvider,
  ) {
    final isSelected = themeProvider.themeMode == mode;
    return InkWell(
      onTap: () => themeProvider.setThemeMode(mode),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 32, color: isSelected ? Theme.of(context).primaryColor : null),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Theme.of(context).primaryColor : null,
              ),
            ),
            const Spacer(),
            if (isSelected) Icon(Icons.check_circle, color: Theme.of(context).primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildAppLockPage(SecurityProvider securityProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          const Icon(
            Icons.lock_outline,
            size: 80,
            color: Colors.orange,
          ),
          const SizedBox(height: 24),
          const Text(
            'Secure Your App',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Would you like to set a PIN to protect your app?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 32),
          SwitchListTile(
            title: const Text('Enable App Lock'),
            subtitle: const Text('Secure your app with a 4-digit PIN'),
            value: securityProvider.isAppLockEnabled,
            onChanged: (value) {
              if (value) {
                _showSetPinDialog(context, securityProvider);
              } else {
                securityProvider.setAppLockEnabled(false);
                setState(() {});
              }
            },
          ),
          const SizedBox(height: 16),
          FutureBuilder<bool>(
            future: securityProvider.checkBiometricAvailable(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data == true && securityProvider.isAppLockEnabled) {
                return SwitchListTile(
                  title: const Text('Use Biometric Authentication'),
                  subtitle: const Text('Use fingerprint or face unlock'),
                  value: securityProvider.isBiometricEnabled,
                  onChanged: securityProvider.isAppLockEnabled
                      ? (value) async {
                          if (value) {
                            // Show biometric authentication dialog
                            final authenticated = await securityProvider.authenticateWithBiometrics();
                            if (authenticated) {
                              await securityProvider.setBiometricEnabled(true);
                            }
                          } else {
                            await securityProvider.setBiometricEnabled(false);
                          }
                          setState(() {});
                        }
                      : null,
                );
              }
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
    );
  }

  Future<void> _showSetPinDialog(BuildContext context, SecurityProvider securityProvider) async {
    _pinController.clear();
    _errorMessage = '';
    String? firstPin;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Set PIN'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: firstPin == null ? 'Enter 4-digit PIN' : 'Confirm PIN',
                      errorText: _errorMessage.isNotEmpty ? _errorMessage : null,
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    if (_pinController.text.length != 4) {
                      setState(() {
                        _errorMessage = 'PIN must be 4 digits';
                      });
                      return;
                    }

                    if (firstPin == null) {
                      firstPin = _pinController.text;
                      _pinController.clear();
                      setState(() {
                        _errorMessage = '';
                      });
                    } else {
                      if (firstPin == _pinController.text) {
                        await securityProvider.setPin(_pinController.text);
                        await securityProvider.setAppLockEnabled(true);
                        Navigator.of(dialogContext).pop();
                        this.setState(() {});
                      } else {
                        setState(() {
                          _errorMessage = 'PINs do not match';
                          _pinController.clear();
                          firstPin = null;
                        });
                      }
                    }
                  },
                  child: Text(firstPin == null ? 'Next' : 'Confirm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currencyProvider = Provider.of<CurrencyProvider>(context);
    final securityProvider = Provider.of<SecurityProvider>(context);

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
        child: _showIntro
          ? _buildIntroScreen(context)
          : SafeArea(
          child: Column(
            children: [
              // Logo and App Name Section
              Container(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/app_logo.png',
                      height: 80,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'BazarHive',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Welcome to BazarHive!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withOpacity(0.8)
                            : Colors.black.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Onboarding Content Section
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                      _isLastPage = index == 2;
                    });
                  },
                  children: [
                    // Currency Settings Page
                    _buildCurrencyPage(currencyProvider),
                    
                    // Theme Settings Page
                    _buildThemePage(themeProvider),
                    
                    // App Lock Page
                    _buildAppLockPage(securityProvider),
                  ],
                ),
              ),
              
              // Navigation Buttons
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        if (_currentPage > 0) {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          _completeOnboarding();
                        }
                      },
                      child: Text(_currentPage > 0 ? 'Back' : 'Skip'),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < 3; i++)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentPage == i
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey.shade300,
                            ),
                          ),
                      ],
                    ),
                    TextButton(
                      onPressed: _nextPage,
                      child: Text(_isLastPage ? 'Finish' : 'Next'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroScreen(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/app_logo.png', height: 120, width: 120),
            const SizedBox(height: 32),
            DefaultTextStyle(
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
              child: AnimatedTextKit(
                isRepeatingAnimation: false,
                totalRepeatCount: 1,
                animatedTexts: [
                  TyperAnimatedText('Welcome to BazarHive'),
                  TyperAnimatedText('Your Smart Bazar Manager'),
                  TyperAnimatedText('Let\'s get you set up!'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'A few quick steps to personalize your experience.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: isDark ? Colors.white70 : Colors.black54),
            ),
            const SizedBox(height: 48),
            _AnimatedGradientButton(
              onTap: () => setState(() => _showIntro = false),
              child: const Text('Get Started', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

// Animated gradient background button
class _AnimatedGradientButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _AnimatedGradientButton({required this.child, required this.onTap});

  @override
  State<_AnimatedGradientButton> createState() => _AnimatedGradientButtonState();
}

class _AnimatedGradientButtonState extends State<_AnimatedGradientButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final Color start1 = const Color(0xFF388E3C); // Light green
        final Color end1 = const Color(0xFF1B5E20);   // Dark green
        final Color start2 = const Color(0xFF2E7D32); // Medium green
        final Color end2 = const Color(0xFF66BB6A);   // Lighter green
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(start1, end1, t)!,
                    Color.lerp(start2, end2, t)!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4)),
                ],
              ),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}
