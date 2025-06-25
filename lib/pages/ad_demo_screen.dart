import 'package:flutter/material.dart';
import 'package:BazarHive/services/ad_helper.dart';

class AdDemoScreen extends StatefulWidget {
  const AdDemoScreen({super.key});

  @override
  State<AdDemoScreen> createState() => _AdDemoScreenState();
}

class _AdDemoScreenState extends State<AdDemoScreen> {
  final InterstitialAdHelper _adHelper = InterstitialAdHelper();
  bool _isAdLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeAd();
  }

  Future<void> _initializeAd() async {
    setState(() {
      _isAdLoading = true;
    });

    // Initialize the Mobile Ads SDK
    await _adHelper.initialize();
    
    // Load the interstitial ad
    await _adHelper.loadAd();
    
    setState(() {
      _isAdLoading = false;
    });
  }

  @override
  void dispose() {
    // Dispose the ad when the screen is disposed
    _adHelper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Interstitial Ad Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isAdLoading)
              const CircularProgressIndicator()
            else
              Text(
                _adHelper.isAdLoaded ? 'Ad is loaded and ready!' : 'Ad is not loaded yet',
                style: const TextStyle(fontSize: 16),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _adHelper.isAdLoaded
                  ? () async {
                      final shown = await _adHelper.showAdIfLoaded();
                      if (!shown && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ad failed to show or was not loaded'),
                          ),
                        );
                      }
                    }
                  : null,
              child: const Text('Show Interstitial Ad'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                setState(() {
                  _isAdLoading = true;
                });
                await _adHelper.loadAd();
                setState(() {
                  _isAdLoading = false;
                });
              },
              child: const Text('Reload Ad'),
            ),
          ],
        ),
      ),
    );
  }
}
