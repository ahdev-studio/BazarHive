import 'package:flutter/material.dart';
import '../widgets/banner_ad_widget.dart';

class SampleScreen extends StatelessWidget {
  const SampleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sample Screen'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Text('Your content goes here'),
            ),
          ),
          // Banner Ad at the bottom
          const BannerAdWidget(),
        ],
      ),
    );
  }
}
