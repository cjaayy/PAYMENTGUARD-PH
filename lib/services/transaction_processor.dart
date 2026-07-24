import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/transaction_model.dart';
import '../utils/sms_parser.dart';
import 'duplicate_checker_service.dart';
import 'voice_alert_service.dart';

/// Central Controller orchestrating SMS parsing, offline duplicate checking,
/// Tagalog voice alerts, and Cloud Firestore synchronization.
class TransactionProcessor {
  final DuplicateCheckerService _duplicateChecker;
  final VoiceAlertService _voiceAlert;
  final FirebaseFirestore? _firestore;

  TransactionProcessor({
    required DuplicateCheckerService duplicateChecker,
    required VoiceAlertService voiceAlert,
    FirebaseFirestore? firestore,
  })  : _duplicateChecker = duplicateChecker,
        _voiceAlert = voiceAlert,
        _firestore = firestore ?? _tryGetFirestore();

  /// Helper to safely resolve Firestore instance without crashing if uninitialized.
  static FirebaseFirestore? _tryGetFirestore() {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      debugPrint('[TransactionProcessor] Firestore instance unavailable during initialization.');
      return null;
    }
  }

  /// Processes an incoming raw e-wallet SMS text alert.
  /// 
  /// 1. Parses SMS using [SmsParser].
  /// 2. Checks local Hive cache via [DuplicateCheckerService].
  /// 3. Triggers voice alert via [VoiceAlertService].
  /// 4. Pushes verified or duplicate rejected record to Firestore `transactions` collection.
  Future<TransactionModel?> processIncomingSms(
    String smsBody, {
    String? senderHeader,
    String merchantId = 'DEFAULT_MERCHANT_01',
  }) async {
    // 1. Parse SMS
    final parsedResult = SmsParser.parse(smsBody, senderHeader: senderHeader);

    if (!parsedResult.isValid) {
      debugPrint('[TransactionProcessor] Ignored SMS: ${parsedResult.errorMessage}');
      return null;
    }

    final refNumber = parsedResult.refNumber!;
    final amount = parsedResult.amount!;
    final senderName = parsedResult.senderName!;
    final source = parsedResult.source;
    final timestamp = DateTime.now();

    // 2. Offline Duplicate Check using Hive
    final isDuplicate = _duplicateChecker.isReferenceDuplicate(refNumber);

    if (isDuplicate) {
      debugPrint('[TransactionProcessor] DUPLICATE DETECTED for ref: $refNumber');

      // a. Voice Warning Alert
      await _voiceAlert.speakDuplicateWarning(refNumber: refNumber);

      // b. Build Duplicate Rejected Transaction Object
      final duplicateTx = TransactionModel(
        id: 'tx_${timestamp.millisecondsSinceEpoch}',
        merchantId: merchantId,
        amount: amount,
        refNumber: refNumber,
        senderName: senderName,
        source: source,
        timestamp: timestamp,
        status: TransactionStatus.duplicateRejected.value,
      );

      // c. Push to Cloud Firestore
      await _pushToFirestore(duplicateTx);

      return duplicateTx;
    }

    // 3. VERIFIED NEW TRANSACTION
    // a. Save reference number locally in Hive
    await _duplicateChecker.saveReferenceLocally(refNumber);

    // b. Trigger Voice Alert ("Pumasok na ang [amount] pesos mula kay [senderName]")
    await _voiceAlert.speakPaymentReceived(amount: amount, senderName: senderName);

    // c. Build Verified Transaction Object
    final verifiedTx = TransactionModel(
      id: 'tx_${timestamp.millisecondsSinceEpoch}',
      merchantId: merchantId,
      amount: amount,
      refNumber: refNumber,
      senderName: senderName,
      source: source,
      timestamp: timestamp,
      status: TransactionStatus.verified.value,
    );

    // d. Push to Cloud Firestore (`transactions` collection)
    await _pushToFirestore(verifiedTx);

    return verifiedTx;
  }

  /// Pushes a transaction object to Cloud Firestore `transactions` collection.
  Future<void> _pushToFirestore(TransactionModel tx) async {
    if (_firestore == null) {
      debugPrint('[TransactionProcessor] Firestore disabled or uninitialized. Skipping cloud sync for tx ${tx.id}.');
      return;
    }

    try {
      await _firestore!
          .collection('transactions')
          .doc(tx.id)
          .set(tx.toMap(), SetOptions(merge: true));

      debugPrint('[TransactionProcessor] Successfully synced transaction ${tx.id} to Firestore (Status: ${tx.status}).');
    } catch (e) {
      debugPrint('[TransactionProcessor] Firestore sync error: $e');
    }
  }
}
