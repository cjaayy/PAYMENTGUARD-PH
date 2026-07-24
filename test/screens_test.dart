import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:paymentguard_ph/screens/mobile_home_screen.dart';
import 'package:paymentguard_ph/screens/platform_router.dart';
import 'package:paymentguard_ph/screens/web_dashboard_screen.dart';
import 'package:paymentguard_ph/services/duplicate_checker_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('hive_screens_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<String>(kVerifiedRefNumbersBox);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Screen Widget Tests', () {
    testWidgets('PlatformRouter renders MobileHomeScreen or WebDashboardScreen cleanly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PlatformRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlatformRouter), findsOneWidget);
    });

    testWidgets('MobileHomeScreen renders status card and dev simulator button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MobileHomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PaymentGuard Protection Active'), findsOneWidget);
      expect(find.text('Simulate Test SMS'), findsOneWidget);
    });

    testWidgets('WebDashboardScreen renders owner dashboard metrics and counter mode button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: WebDashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Total Sales Volume Today'), findsOneWidget);
      expect(find.text('Customer Counter View'), findsOneWidget);
    });
  });
}
