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
  /// 1. Parses SMS using [SmsParser] (detects amount, ref, sender, e-wallet, and phishing links/keywords).
  /// 2. Handles Scam/Phishing SMS (triggers Tagalog scam voice alert & pushes HIGH threat record to Firestore).
  /// 3. Checks local Hive cache for duplicate reference numbers.
  /// 4. Triggers Tagalog voice alert via [VoiceAlertService].
  /// 5. Pushes record to Cloud Firestore `transactions` collection.
  Future<TransactionModel?> processIncomingSms(
    String smsBody, {
    String? senderHeader,
    String merchantId = 'DEFAULT_MERCHANT_01',
  }) async {
    // 1. Parse SMS
    final parsedResult = SmsParser.parse(smsBody, senderHeader: senderHeader);

    if (!parsedResult.isValid && !parsedResult.isScam) {
      debugPrint('[TransactionProcessor] Ignored SMS: ${parsedResult.errorMessage}');
      return null;
    }

    final timestamp = DateTime.now();
    final source = parsedResult.source;

    // 2. PHISHING / SCAM SMS HANDLING
    if (parsedResult.isScam) {
      debugPrint('[TransactionProcessor] SCAM DETECTED: ${parsedResult.rawBody}');

      // a. Urgent English Voice Scam Alert
      await _voiceAlert.speakScamWarningAlert(senderName: parsedResult.senderName);

      // b. Build Scam Transaction Object
      final scamTx = TransactionModel(
        id: 'tx_scam_${timestamp.millisecondsSinceEpoch}',
        merchantId: merchantId,
        amount: parsedResult.amount,
        refNumber: parsedResult.refNumber ?? 'NO_REF',
        senderName: parsedResult.senderName ?? 'PHISHING SENDER',
        source: source,
        timestamp: timestamp,
        status: 'SCAM_FLAGGED',
        sender: source,
        message: smsBody,
        isScam: true,
        threatLevel: 'HIGH',
      );

      // c. Push to Cloud Firestore `transactions` collection
      await _pushToFirestore(scamTx);

      return scamTx;
    }

    final refNumber = parsedResult.refNumber!;
    final amount = parsedResult.amount;
    final senderName = parsedResult.senderName!;

    // 3. OFFLINE DUPLICATE CHECK USING HIVE
    final isDuplicate = _duplicateChecker.isReferenceDuplicate(refNumber);

    if (isDuplicate) {
      debugPrint('[TransactionProcessor] DUPLICATE DETECTED for ref: $refNumber');

      // a. Tagalog Voice Duplicate Warning
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
        sender: source,
        message: smsBody,
        isScam: false,
        threatLevel: 'LOW',
      );

      // c. Push to Cloud Firestore
      await _pushToFirestore(duplicateTx);

      return duplicateTx;
    }

    // 4. VERIFIED NEW LEGIT TRANSACTION
    // a. Save reference number locally in Hive
    await _duplicateChecker.saveReferenceLocally(refNumber);

    // b. Trigger English Voice Alert ("Received [Amount] pesos via [Provider]. Reference number [RefNo].")
    await _voiceAlert.speakLegitPaymentAlert(
      amount: amount,
      senderName: senderName,
      refNumber: refNumber,
      provider: parsedResult.provider,
    );

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
      sender: source,
      message: smsBody,
      isScam: false,
      threatLevel: 'LOW',
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
      final dataMap = tx.toMap(useServerTimestamp: true);

      await _firestore!
          .collection('transactions')
          .doc(tx.id)
          .set(dataMap, SetOptions(merge: true));

      debugPrint('[TransactionProcessor] Successfully synced transaction ${tx.id} to Firestore (isScam: ${tx.isScam}, threatLevel: ${tx.threatLevel}).');
    } catch (e) {
      debugPrint('[TransactionProcessor] Firestore sync error: $e');
    }
  }
}
