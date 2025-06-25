import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TermsDialogBazarHive extends StatelessWidget {
  const TermsDialogBazarHive({super.key});

  static const String _termsAcceptedKey = 'bazarhive_terms_accepted';

  /// Checks if the terms dialog should be shown based on whether
  /// the user has previously accepted the terms.
  static Future<bool> shouldShowTerms() async {
    final prefs = await SharedPreferences.getInstance();
    final hasAccepted = prefs.getBool(_termsAcceptedKey) ?? false;
    return !hasAccepted;
  }

  /// Marks the terms as accepted in SharedPreferences.
  static Future<void> markTermsAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_termsAcceptedKey, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Terms & Conditions',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'By using BazarHive, you agree to the following terms:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            _buildTermItem('BazarHive does not collect or share your personal data.'),
            _buildTermItem('You are responsible for the accuracy of your shopping data entries.'),
            _buildTermItem('You can export and share shopping lists, but the app is not responsible for shared data usage.'),
            _buildTermItem('This app is designed for personal and household shopping management only.'),
            _buildTermItem('Features and policies may change in future updates.'),
            const SizedBox(height: 16),
            const Text(
              'By tapping "Accept", you agree to these terms. If you do not agree, tap "Decline" to exit the app.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            // Exit the app
            SystemNavigator.pop();
          },
          child: const Text(
            'Decline',
            style: TextStyle(color: Colors.red),
          ),
        ),
        FilledButton(
          onPressed: () async {
            await markTermsAccepted();
            if (context.mounted) {
              Navigator.pop(context, true);
            }
          },
          child: const Text('Accept'),
        ),
      ],
    );
  }

  Widget _buildTermItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: Text(text),
          ),
        ],
      ),
    );
  }
}
