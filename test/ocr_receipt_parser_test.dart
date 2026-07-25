import 'package:flutter_test/flutter_test.dart';
import 'package:paymentguard_ph/utils/ocr_receipt_parser.dart';
import 'package:paymentguard_ph/utils/provider_detector.dart';

void main() {
  group('ProviderDetector Unit Tests', () {
    test('Detects MariBank from maribank keyword or MB header', () {
      expect(ProviderDetector.detect('Received PHP 500 from MariBank'), equals('MariBank'));
      expect(ProviderDetector.detect('Transfer alert', senderHeader: 'MB'), equals('MariBank'));
    });

    test('Detects Maya from maya or paymaya keywords', () {
      expect(ProviderDetector.detect('Payment via Maya received'), equals('Maya'));
      expect(ProviderDetector.detect('PayMaya transaction alert'), equals('Maya'));
    });

    test('Detects GCash from gcash keyword or Express Send', () {
      expect(ProviderDetector.detect('You received PHP 150 of GCash'), equals('GCash'));
      expect(ProviderDetector.detect('Express Send payment'), equals('GCash'));
    });

    test('Defaults to Unknown Provider when no keywords match', () {
      expect(ProviderDetector.detect('Generic bank transfer received'), equals('Unknown Provider'));
    });
  });

  group('OcrReceiptParser - Automatic Provider Detection & Parsing', () {
    test('Detects MariBank receipt and sets provider field', () {
      const rawOcrText = '''
MARIBANK
Transaction Confirmation
Amount: PHP 1,800.00
Ref No. 100987654321
''';
      final result = OcrReceiptParser.parse(rawOcrText);

      expect(result.provider, equals('MariBank'));
      expect(result.walletType, equals('MariBank'));
      expect(result.sender, equals('MariBank (Scanned)'));
      expect(result.amount, equals(1800.00));
      expect(result.referenceNo, equals('100987654321'));
    });

    test('Defaults sender to GCash (Scanned) when sender is garbled header text', () {
      const rawOcrText = '''
EXPRESS SEND
GCASH
TRANSACTION DETAILS
Amount: PHP 500.00
Ref No. 1002938475610
BANGKO SENTRAL NG PILIPINAS
''';
      final result = OcrReceiptParser.parse(rawOcrText);

      expect(result.provider, equals('GCash'));
      expect(result.sender, equals('GCash (Scanned)'));
      expect(result.amount, equals(500.00));
      expect(result.referenceNo, equals('1002938475610'));
    });

    test('Defaults sender to Maya (Scanned) for Maya receipt with garbled header', () {
      const rawOcrText = '''
MAYA
PAYMENT SUCCESS
Total Amount: ₱ 1,250.00
Reference No: 987654321012
Regulated by the Bangko Sentral ng Pilipinas
''';
      final result = OcrReceiptParser.parse(rawOcrText);

      expect(result.provider, equals('Maya'));
      expect(result.sender, equals('Maya (Scanned)'));
      expect(result.amount, equals(1250.00));
      expect(result.referenceNo, equals('987654321012'));
    });

    test('Extracts explicit clean sender name when clearly present', () {
      const rawOcrText = '''
GCash Express Send
Sent by
JUAN DELA CRUZ
09171234567
Amount: PHP 750.00
Ref No. 1002938475000
''';
      final result = OcrReceiptParser.parse(rawOcrText);

      expect(result.sender, equals('JUAN DELA CRUZ'));
      expect(result.amount, equals(750.00));
      expect(result.referenceNo, equals('1002938475000'));
    });
  });

  group('OcrReceiptParser - Requirement 2: Footer & Banner Noise Stripping', () {
    test('Strips out common non-transaction text such as BSP, Para sa Pilipinas, Buy Load', () {
      const noisyText = '''
EXPRESS SEND
Bangko Sentral ng Pilipinas
Para sa Pilipinas
Buy Load
Amount: PHP 300.00
Ref No. 1002938475678
Share Receipt
Save to Photos
''';
      final cleanedText = OcrReceiptParser.stripNoise(noisyText);

      expect(cleanedText, contains('Amount: PHP 300.00'));
      expect(cleanedText, contains('Ref No. 1002938475678'));
      expect(cleanedText, isNot(contains('Bangko Sentral ng Pilipinas')));
      expect(cleanedText, isNot(contains('Para sa Pilipinas')));
      expect(cleanedText, isNot(contains('Buy Load')));
      expect(cleanedText, isNot(contains('Share Receipt')));

      final result = OcrReceiptParser.parse(noisyText);
      expect(result.amount, equals(300.00));
      expect(result.referenceNo, equals('1002938475678'));
    });
  });

  group('OcrReceiptParser - Requirement 3: Amount Parsing Accuracy', () {
    test('Accurately parses amount following PHP/₱ and ignores digits in time and ref no', () {
      const ocrText = '''
GCash Receipt
Time: 10:45 PM
Date: 2026-07-25
Amount: PHP 2,450.75
Ref No: 1002938475610
Help Center
''';
      final result = OcrReceiptParser.parse(ocrText);

      expect(result.amount, equals(2450.75));
      expect(result.referenceNo, equals('1002938475610'));
    });

    test('Parses amount preceded by ₱ currency symbol', () {
      const ocrText = '''
Maya Payment Details
Total Amount
₱ 150.00
Reference No. 987654321099
Time: 12:30:15
''';
      final result = OcrReceiptParser.parse(ocrText);

      expect(result.amount, equals(150.00));
      expect(result.referenceNo, equals('987654321099'));
    });
  });

  group('OcrReceiptParser - Requirement 4: Prevent False Scam Flags', () {
    test('Defaults isScam to false and threatLevel to LOW for legitimate OCR receipts', () {
      const validReceipt = '''
GCash Express Send
Sent by MARIA CLARA
Amount: PHP 500.00
Ref No. 1002938475111
Bangko Sentral ng Pilipinas
''';
      final result = OcrReceiptParser.parse(validReceipt);

      expect(result.isValid, isTrue);
      expect(result.isScam, isFalse);
      expect(result.threatLevel, equals('LOW'));
    });

    test('Flags isScam to true and threatLevel to HIGH when a phishing URL is found', () {
      const scamReceipt = '''
GCash Security Alert
Amount: PHP 1,000.00
Ref No: 1002938475222
Please verify your account immediately at: http://gcash-verify-login.phish-site.com/claim
''';
      final result = OcrReceiptParser.parse(scamReceipt);

      expect(result.isScam, isTrue);
      expect(result.threatLevel, equals('HIGH'));
      expect(result.errorMessage, contains('PHISHING'));
    });
  });
}
