import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import '../utils/provider_detector.dart';
import '../utils/sms_parser.dart';
import 'transaction_processor.dart';

/// Container representing a parsed incoming app push notification from an e-wallet.
class ParsedNotificationResult {
  final double? amount;
  final String? referenceNo;
  final String provider; // 'GCash', 'Maya', 'MariBank', or 'Unknown Provider'
  final String packageName;
  final String title;
  final String text;
  final bool isValid;

  const ParsedNotificationResult({
    this.amount,
    this.referenceNo,
    required this.provider,
    required this.packageName,
    required this.title,
    required this.text,
    required this.isValid,
  });
}

/// Service to listen for real-time Android push notifications from e-wallet apps
/// (GCash, Maya, MariBank) and push verified transactions to Cloud Firestore.
class AppNotificationListenerService {
  static const Set<String> _targetPackages = {
    'com.globe.gcash.android', // GCash Official App
    'com.paymaya',              // Maya / PayMaya Official App
    'com.maribank.ph',          // MariBank App
    'com.seabank.ph',           // SeaBank App
    'com.shopee.ph',            // Shopee / MariBank Ecosystem
  };

  /// Parses an incoming notification event to extract e-wallet payment details.
  static ParsedNotificationResult parseNotification({
    required String packageName,
    required String title,
    required String text,
  }) {
    final String combinedContent = '$title $text';
    final String lowerPkg = packageName.toLowerCase();

    // 1. Determine Provider based on package name first, with text fallback
    String provider = 'Unknown Provider';
    if (lowerPkg.contains('gcash')) {
      provider = 'GCash';
    } else if (lowerPkg.contains('paymaya') || lowerPkg.contains('maya')) {
      provider = 'Maya';
    } else if (lowerPkg.contains('maribank') || lowerPkg.contains('seabank') || lowerPkg.contains('shopee')) {
      provider = 'MariBank';
    } else {
      provider = ProviderDetector.detect(combinedContent);
    }

    // 2. Extract Amount using regex
    final double? amount = SmsParser.extractAmount(combinedContent);

    // 3. Extract Reference Number using regex (10-13 digits or Ref string)
    String? refNo = SmsParser.extractRefNumber(combinedContent);
    if (refNo == null || refNo.isEmpty) {
      // Fallback: look for 10 to 13 consecutive digits in the text
      final digitMatch = RegExp(r'\b\d{10,13}\b').firstMatch(combinedContent);
      if (digitMatch != null) {
        refNo = digitMatch.group(0);
      }
    }

    final bool isValid = (amount != null && amount > 0) || (refNo != null && refNo.isNotEmpty);

    return ParsedNotificationResult(
      amount: amount,
      referenceNo: refNo ?? 'N/A',
      provider: provider,
      packageName: packageName,
      title: title,
      text: text,
      isValid: isValid,
    );
  }

  /// Processes an incoming notification event, runs transaction checks, and saves to Firestore.
  static Future<void> processNotificationEvent(
    NotificationEvent evt, {
    required TransactionProcessor processor,
    Function(String message, bool isError)? onStatusUpdate,
  }) async {
    final String packageName = evt.packageName ?? '';
    final String title = evt.title ?? '';
    final String text = evt.text ?? evt.message ?? '';

    debugPrint('🔔 [NotificationListener] Received notification from: $packageName');
    debugPrint('   Title: $title | Text: $text');

    // 1. Package Filtering: Only process targeted e-wallets unless text explicitly matches
    final bool isTargetPackage = _targetPackages.contains(packageName.toLowerCase()) ||
        _targetPackages.any((pkg) => packageName.toLowerCase().contains(pkg));

    final String detectedProvider = ProviderDetector.detect('$title $text');
    final bool isKnownProvider = detectedProvider != 'Unknown Provider';

    if (!isTargetPackage && !isKnownProvider) {
      debugPrint('   Ignored: Package $packageName is not a targeted e-wallet.');
      return;
    }

    // 2. Parse details
    final parsed = parseNotification(
      packageName: packageName,
      title: title,
      text: text,
    );

    if (!parsed.isValid) {
      debugPrint('   Ignored: Notification does not contain valid payment details.');
      return;
    }

    // 3. Current Store User ID
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      debugPrint('❌ [NotificationListener] Error: No store user logged in.');
      onStatusUpdate?.call('No store user logged in.', true);
      return;
    }

    // 4. Process transaction via TransactionProcessor for duplicate checking & voice alerts
    final String fullText = '$title: $text';
    final processedTx = await processor.processIncomingSms(
      fullText,
      senderHeader: parsed.provider,
      merchantId: currentUserId,
    );

    // 5. Push document to Firestore transactions collection
    try {
      await FirebaseFirestore.instance.collection('transactions').add({
        'amount': parsed.amount ?? (processedTx?.amount ?? 0.0),
        'provider': parsed.provider,
        'sender': parsed.provider,
        'sender_name': processedTx?.senderName ?? parsed.provider,
        'reference_no': parsed.referenceNo != 'N/A' ? parsed.referenceNo : (processedTx?.refNumber ?? 'N/A'),
        'store_id': currentUserId,
        'status': processedTx?.status ?? 'VERIFIED',
        'isScam': processedTx?.isScam ?? false,
        'timestamp': FieldValue.serverTimestamp(),
        'raw_message': fullText,
        'package_name': packageName,
      });

      debugPrint('✅ [NotificationListener] Saved notification transaction to Firestore!');
      onStatusUpdate?.call('✅ Saved ${parsed.provider} notification payment!', false);
    } catch (e) {
      debugPrint('❌ [NotificationListener] Firestore write error: $e');
      onStatusUpdate?.call('Firestore save error: $e', true);
    }
  }

  /// Checks if Notification Listener Service permission is granted on Android.
  static Future<bool> isPermissionGranted() async {
    try {
      final bool? isPermissionGranted = await NotificationsListener.hasPermission;
      return isPermissionGranted ?? false;
    } catch (e) {
      debugPrint('⚠️ Warning: Notification listener permission check error: $e');
      return false;
    }
  }

  /// Prompts user to grant Android Notification Listener access in Settings.
  static Future<void> requestPermission() async {
    try {
      await NotificationsListener.openPermissionSettings();
    } catch (e) {
      debugPrint('⚠️ Warning: Open notification settings error: $e');
    }
  }
}
