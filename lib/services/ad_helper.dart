import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:async';

class InterstitialAdHelper {
  // Ad Unit ID
  static const String adUnitId = 'ca-app-pub-2075727745408240/5740513851';
  
  // Test Ad Unit ID for development
  static const String testAdUnitId = 'ca-app-pub-3940256099942544/1033173712';
  
  // Flag to use test ads during development
  static const bool useTestAds = false;
  
  // Singleton instance
  static final InterstitialAdHelper _instance = InterstitialAdHelper._internal();
  
  // Factory constructor
  factory InterstitialAdHelper() => _instance;
  
  // Internal constructor
  InterstitialAdHelper._internal();
  
  // Interstitial ad instance
  InterstitialAd? _interstitialAd;
  
  // Flag to track if ad is loaded
  bool _isAdLoaded = false;
  
  // Getter for ad loaded state
  bool get isAdLoaded => _isAdLoaded;
  
  // Initialize the ad
  Future<void> initialize() async {
    // Initialize the Mobile Ads SDK
    await MobileAds.instance.initialize();
  }
  
  // Load the interstitial ad
  Future<void> loadAd() async {
    if (_interstitialAd != null) {
      return;
    }
    
    try {
      // Use a timeout to prevent hanging if ad loading takes too long
      await InterstitialAd.load(
        adUnitId: useTestAds ? testAdUnitId : adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (InterstitialAd ad) {
            debugPrint('Interstitial ad loaded successfully');
            _interstitialAd = ad;
            _isAdLoaded = true;
            
            // Set full screen content callback
            _setFullScreenContentCallback();
          },
          onAdFailedToLoad: (LoadAdError error) {
            debugPrint('Interstitial ad failed to load: ${error.message}');
            _isAdLoaded = false;
            _interstitialAd = null;
            
            // Retry loading after a delay if it failed
            Future.delayed(const Duration(minutes: 1), () {
              loadAd();
            });
          },
        ),
      );
    } catch (e) {
      debugPrint('Error loading interstitial ad: $e');
      _isAdLoaded = false;
      _interstitialAd = null;
    }
  }
  
  // Set full screen content callback
  void _setFullScreenContentCallback() {
    if (_interstitialAd == null) return;
    
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (InterstitialAd ad) {
        debugPrint('Interstitial ad showed full screen content');
      },
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        debugPrint('Interstitial ad dismissed full screen content');
        ad.dispose();
        _interstitialAd = null;
        _isAdLoaded = false;
        
        // Reload the ad for next time
        loadAd();
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        debugPrint('Interstitial ad failed to show full screen content: ${error.message}');
        ad.dispose();
        _interstitialAd = null;
        _isAdLoaded = false;
        
        // Reload the ad for next time
        loadAd();
      },
    );
  }
  
  // Show the ad if it's loaded
  Future<bool> showAdIfLoaded() async {
    if (_interstitialAd == null || !_isAdLoaded) {
      debugPrint('Interstitial ad not loaded yet');
      // Try to load the ad for next time
      loadAd();
      return false;
    }
    
    try {
      // Use a completer to handle the async operation properly
      final completer = Completer<bool>();
      
      // Show the ad
      _interstitialAd!.show().then((_) {
        completer.complete(true);
      }).catchError((e) {
        debugPrint('Error showing interstitial ad: $e');
        _interstitialAd = null;
        _isAdLoaded = false;
        loadAd(); // Try to reload
        completer.complete(false);
      });
      
      return completer.future;
    } catch (e) {
      debugPrint('Error showing interstitial ad: $e');
      _interstitialAd = null;
      _isAdLoaded = false;
      loadAd(); // Try to reload
      return false;
    }
  }
  
  // Dispose the ad
  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _isAdLoaded = false;
  }
}
