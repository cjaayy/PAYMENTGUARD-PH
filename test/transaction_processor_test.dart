import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:paymentguard_ph/models/transaction_model.dart';
import 'package:paymentguard_ph/services/duplicate_checker_service.dart';
import 'package:paymentguard_ph/services/transaction_processor.dart';
import 'package:paymentguard_ph/services/voice_alert_service.dart';

/// Mock Voice Alert Service that records audio triggers without playing real sound during tests.
class MockVoiceAlertService extends VoiceAlertService {
  String? lastSpokenText;
  bool paymentAlertSpoken = false;
  bool duplicateWarningSpoken = false;

  @override
  Future<void> speakLegitPaymentAlert({
    required double? amount,
    required String senderName,
    required String? refNumber,
    String? provider,
  }) async {
    paymentAlertSpoken = true;
    lastSpokenText = 'Received $amount pesos from $senderName. Reference number $refNumber.';
  }

  @override
  Future<void> speakPaymentReceived({double? amount, String? senderName, String? refNumber}) async {
    paymentAlertSpoken = true;
    lastSpokenText = 'Received $amount pesos from $senderName. Reference number $refNumber.';
  }

  @override
  Future<void> speakDuplicateWarning({required String refNumber}) async {
    duplicateWarningSpoken = true;
    lastSpokenText = 'Warning! Reference number $refNumber has already been used.';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<String>(kVerifiedRefNumbersBox);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('TransactionProcessor Unit Tests', () {
    test('Processes new verified GCash SMS, saves to Hive, and triggers payment voice alert', () async {
      final hiveBox = Hive.box<String>(kVerifiedRefNumbersBox);
      final duplicateChecker = DuplicateCheckerService(hiveBox);
      final mockVoice = MockVoiceAlertService();

      final processor = TransactionProcessor(
        duplicateChecker: duplicateChecker,
        voiceAlert: mockVoice,
        firestore: null, // Null for offline testing
      );

      const sms = 'You have received PHP 250.00 of GCash from MARIA CLARA 09171234567 with Ref. No. 900800700600 on 07/25/2026.';
      final result = await processor.processIncomingSms(sms, senderHeader: 'GCash');

      expect(result, isNotNull);
      expect(result!.isVerified, isTrue);
      expect(result.amount, equals(250.00));
      expect(result.refNumber, equals('900800700600'));
      expect(result.senderName, equals('MARIA CLARA'));
      expect(result.status, equals(TransactionStatus.verified.value));

      // Verify Hive save
      expect(duplicateChecker.isReferenceDuplicate('900800700600'), isTrue);

      // Verify Voice Alert
      expect(mockVoice.paymentAlertSpoken, isTrue);
    });

    test('Flags duplicate reference number on second SMS and triggers warning voice alert', () async {
      final hiveBox = Hive.box<String>(kVerifiedRefNumbersBox);
      final duplicateChecker = DuplicateCheckerService(hiveBox);
      final mockVoice = MockVoiceAlertService();

      final processor = TransactionProcessor(
        duplicateChecker: duplicateChecker,
        voiceAlert: mockVoice,
        firestore: null,
      );

      const sms = 'You received P500.00 from JUAN DELA CRUZ via Maya. Ref No: 112233445566.';

      // First time -> Verified
      final firstResult = await processor.processIncomingSms(sms, senderHeader: 'Maya');
      expect(firstResult!.isVerified, isTrue);
      expect(mockVoice.paymentAlertSpoken, isTrue);

      // Reset mock flags
      mockVoice.paymentAlertSpoken = false;
      mockVoice.duplicateWarningSpoken = false;

      // Second time with same Ref No -> Duplicate Rejected
      final secondResult = await processor.processIncomingSms(sms, senderHeader: 'Maya');
      expect(secondResult, isNotNull);
      expect(secondResult!.isDuplicate, isTrue);
      expect(secondResult.status, equals(TransactionStatus.duplicateRejected.value));

      // Verify Duplicate Voice Alert was spoken
      expect(mockVoice.duplicateWarningSpoken, isTrue);
    });
  });
}
