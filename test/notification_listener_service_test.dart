import 'package:flutter_test/flutter_test.dart';
import 'package:paymentguard_ph/services/notification_listener_service.dart';

void main() {
  group('AppNotificationListenerService - Notification Parsing Tests', () {
    test('Parses GCash Push Notification cleanly', () {
      const packageName = 'com.globe.gcash.android';
      const title = 'GCash Received';
      const text = 'You have received PHP 500.00 of GCash from JUAN DELA CRUZ with Ref No. 1002987654.';

      final result = AppNotificationListenerService.parseNotification(
        packageName: packageName,
        title: title,
        text: text,
      );

      expect(result.isValid, true);
      expect(result.provider, 'GCash');
      expect(result.amount, 500.00);
      expect(result.referenceNo, '1002987654');
      expect(result.packageName, packageName);
    });

    test('Parses Maya Push Notification cleanly', () {
      const packageName = 'com.paymaya';
      const title = 'Money Received!';
      const text = 'You received P1,250.50 from MARIA CLARA via Maya. Ref No: 987654321012.';

      final result = AppNotificationListenerService.parseNotification(
        packageName: packageName,
        title: title,
        text: text,
      );

      expect(result.isValid, true);
      expect(result.provider, 'Maya');
      expect(result.amount, 1250.50);
      expect(result.referenceNo, '987654321012');
      expect(result.packageName, packageName);
    });

    test('Parses MariBank Push Notification cleanly', () {
      const packageName = 'com.maribank.ph';
      const title = 'Transfer Received';
      const text = 'MariBank: You received PHP 250.00 from PEDRO P. via MariBank transfer. Ref No: MB123456789.';

      final result = AppNotificationListenerService.parseNotification(
        packageName: packageName,
        title: title,
        text: text,
      );

      expect(result.isValid, true);
      expect(result.provider, 'MariBank');
      expect(result.amount, 250.00);
      expect(result.referenceNo, 'MB123456789');
      expect(result.packageName, packageName);
    });

    test('Parses Shopee / MariBank notification cleanly', () {
      const packageName = 'com.shopee.ph';
      const title = 'MariBank Transfer Success';
      const text = 'You received PHP 750.00. Reference No: 8877665544.';

      final result = AppNotificationListenerService.parseNotification(
        packageName: packageName,
        title: title,
        text: text,
      );

      expect(result.isValid, true);
      expect(result.provider, 'MariBank');
      expect(result.amount, 750.00);
      expect(result.referenceNo, '8877665544');
    });

    test('Rejects non-payment app notifications', () {
      const packageName = 'com.social.app';
      const title = 'New Message';
      const text = 'Hey, check out this photo!';

      final result = AppNotificationListenerService.parseNotification(
        packageName: packageName,
        title: title,
        text: text,
      );

      expect(result.isValid, false);
      expect(result.amount, null);
    });
  });
}
