import 'package:flutter_test/flutter_test.dart';
import 'package:paymentguard_ph/utils/sms_parser.dart';

void main() {
  group('SmsParser - GCash SMS Tests', () {
    test('Parses standard GCash SMS format with full details', () {
      const sms = 'You have received PHP 150.00 of GCash from JUAN DELA CRUZ 09171234567 with Ref. No. 102938475610 on 07/25/2026 10:30 AM.';
      final result = SmsParser.parse(sms, senderHeader: 'GCash');

      expect(result.isValid, isTrue);
      expect(result.source, equals('GCash'));
      expect(result.amount, equals(150.00));
      expect(result.refNumber, equals('102938475610'));
      expect(result.senderName, equals('JUAN DELA CRUZ'));
    });

    test('Parses GCash SMS with commas in amount', () {
      const sms = 'You have received Php 1,250.50 of GCash from MARIA SANTOS 09181234567 with Ref. No. 500192837465 on 07/25/2026.';
      final result = SmsParser.parse(sms);

      expect(result.isValid, isTrue);
      expect(result.amount, equals(1250.50));
      expect(result.refNumber, equals('500192837465'));
      expect(result.senderName, equals('MARIA SANTOS'));
    });

    test('Parses short GCash format', () {
      const sms = 'You received PHP 500.00 from JOSE RIZAL with Ref No. 900123456789.';
      final result = SmsParser.parse(sms);

      expect(result.isValid, isTrue);
      expect(result.amount, equals(500.00));
      expect(result.refNumber, equals('900123456789'));
      expect(result.senderName, equals('JOSE RIZAL'));
    });
  });

  group('SmsParser - Maya SMS Tests', () {
    test('Parses standard Maya SMS format', () {
      const sms = 'You received P500.00 from JUAN DELA CRUZ via Maya. Ref No: 987654321012.';
      final result = SmsParser.parse(sms, senderHeader: 'Maya');

      expect(result.isValid, isTrue);
      expect(result.source, equals('Maya'));
      expect(result.amount, equals(500.00));
      expect(result.refNumber, equals('987654321012'));
      expect(result.senderName, equals('JUAN DELA CRUZ'));
    });

    test('Parses Maya SMS with Reference No keyword', () {
      const sms = 'You have received PHP 75.00 from PEDRO PENDUKO via Maya. Reference No: 998877665544.';
      final result = SmsParser.parse(sms);

      expect(result.isValid, isTrue);
      expect(result.source, equals('Maya'));
      expect(result.amount, equals(75.00));
      expect(result.refNumber, equals('998877665544'));
      expect(result.senderName, equals('PEDRO PENDUKO'));
    });
  });

  group('SmsParser - Edge Cases & Failures', () {
    test('Returns invalid result for non-payment SMS', () {
      const sms = 'Your OTP for GCash login is 123456. Do not share this with anyone.';
      final result = SmsParser.parse(sms);

      expect(result.isValid, isFalse);
      expect(result.amount, isNull);
    });

    test('Handles empty SMS text gracefully', () {
      final result = SmsParser.parse('');

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('empty'));
    });
  });
}
