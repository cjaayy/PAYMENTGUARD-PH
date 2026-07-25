import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';
import 'screens/platform_router.dart';
import 'services/duplicate_checker_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Hive for local offline duplicate reference number checks
  await Hive.initFlutter();
  await Hive.openBox<String>(kVerifiedRefNumbersBox);

  // 2. Initialize Firebase with current platform options
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization warning: $e');
  }

  runApp(
    const ProviderScope(
      child: PaymentGuardApp(),
    ),
  );
}

/// Root Application Widget for PaymentGuard PH
class PaymentGuardApp extends StatelessWidget {
  const PaymentGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaymentGuard PH',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF00E676), // Vibrant Emerald Green
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900
        cardColor: const Color(0xFF1E293B), // Slate 800
        typography: Typography.material2021(),
      ),
      // Platform Routing between Mobile Home & Web Dashboard
      home: const PlatformRouter(),
    );
  }
}
