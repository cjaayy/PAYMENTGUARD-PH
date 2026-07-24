import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'mobile_home_screen.dart';
import 'web_dashboard_screen.dart';

/// Platform Router screen that conditionally routes the user based on platform environment (`kIsWeb`).
class PlatformRouter extends StatelessWidget {
  const PlatformRouter({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const WebDashboardScreen();
    } else {
      return const MobileHomeScreen();
    }
  }
}
