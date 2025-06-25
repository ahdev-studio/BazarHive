import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';

class DrawerProfileSection extends StatefulWidget {
  const DrawerProfileSection({Key? key}) : super(key: key);

  @override
  State<DrawerProfileSection> createState() => _DrawerProfileSectionState();
}

class _DrawerProfileSectionState extends State<DrawerProfileSection> {
  String userName = 'Guest User';
  String? profileImagePath;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    // Refresh data every 2 seconds while drawer is open
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        _loadUserData();
      }
    });
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString('userName') ?? 'Guest User';
      profileImagePath = prefs.getString('profileImagePath');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withOpacity(0.8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.grey[200],
            backgroundImage: profileImagePath != null
                ? FileImage(File(profileImagePath!))
                : const AssetImage('assets/images/app_logo.png') as ImageProvider,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () async {
                    final result = await Navigator.pushNamed(context, '/profile');
                    if (mounted && result == true) {
                      _loadUserData(); // Refresh data after returning with changes
                    }
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.edit, size: 16, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'Edit Profile',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
