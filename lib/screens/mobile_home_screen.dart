import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/transaction_model.dart';
import '../services/duplicate_checker_service.dart';
import '../services/transaction_processor.dart';
import '../services/voice_alert_service.dart';
import '../utils/ocr_receipt_parser.dart';
import 'ocr_scanner_screen.dart';

/// Mobile Home Screen designed for store cashiers using an Android phone at the counter.
class MobileHomeScreen extends ConsumerStatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  ConsumerState<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends ConsumerState<MobileHomeScreen> with WidgetsBindingObserver {
  bool _isProtectionActive = true;
  late DuplicateCheckerService _duplicateChecker;
  late VoiceAlertService _voiceAlert;
  late TransactionProcessor _transactionProcessor;

  // Setup & Permissions Checker States
  bool _smsGranted = false;
  bool _notificationGranted = false;
  bool _batteryOptDisabled = false;
  bool _isCheckingPermissions = true;
  bool _isBannerDismissed = false;

  final List<TransactionModel> _transactionsList = [];
  final currencyFormatter = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
    _loadDismissedState();
    _checkPermissions();
    final String? mobileUid = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('MOBILE_AUTH_UID: $mobileUid');
    print('MOBILE_AUTH_UID: $mobileUid');
  }

  Future<void> _loadDismissedState() async {
    try {
      final box = Hive.isBoxOpen('app_settings') ? Hive.box('app_settings') : await Hive.openBox('app_settings');
      if (mounted) {
        setState(() {
          _isBannerDismissed = box.get('dismissed_battery_warning', defaultValue: false);
        });
      }
    } catch (_) {}
  }

  Future<void> _dismissBatteryWarning() async {
    try {
      final box = Hive.isBoxOpen('app_settings') ? Hive.box('app_settings') : await Hive.openBox('app_settings');
      await box.put('dismissed_battery_warning', true);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isBannerDismissed = true;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  /// Checks SMS, Notification, and Battery Optimization permissions with OEM safe fallbacks and debug logs.
  Future<void> _checkPermissions() async {
    if (!mounted) return;

    setState(() {
      _isCheckingPermissions = true;
    });

    bool smsGranted = false;
    bool notificationGranted = false;
    bool batteryOptDisabled = false;

    try {
      final sms = await Permission.sms.status;
      smsGranted = sms.isGranted;
    } catch (e) {
      debugPrint('⚠️ Warning: SMS permission check error: $e');
    }

    try {
      final notification = await Permission.notification.status;
      notificationGranted = notification.isGranted;
    } catch (e) {
      debugPrint('⚠️ Warning: Notification permission check error: $e');
    }

    // Safe battery optimization check for custom Android OEMs (Xiaomi, Samsung, Huawei, etc.)
    try {
      final battery = await Permission.ignoreBatteryOptimizations.status;
      batteryOptDisabled = battery.isGranted;
    } catch (e) {
      debugPrint('⚠️ Warning: Ignore battery optimizations check error on OEM device: $e');
      batteryOptDisabled = true; // Fallback so OEM quirk does not hard-block user
    }

    debugPrint('[PermissionChecker] App resumed / re-checked permission statuses:');
    debugPrint('  - 📱 SMS Permission Granted: $smsGranted');
    debugPrint('  - 🔔 Notification Granted: $notificationGranted');
    debugPrint('  - 🔋 Battery Opt Disabled: $batteryOptDisabled');

    if (mounted) {
      setState(() {
        _smsGranted = smsGranted;
        _notificationGranted = notificationGranted;
        _batteryOptDisabled = batteryOptDisabled;
        _isCheckingPermissions = false;
      });
    }
  }

  void _initServices() {
    final box = Hive.box<String>(kVerifiedRefNumbersBox);
    _duplicateChecker = DuplicateCheckerService(box);
    _voiceAlert = VoiceAlertService();
    _transactionProcessor = TransactionProcessor(
      duplicateChecker: _duplicateChecker,
      voiceAlert: _voiceAlert,
    );
  }

  /// Calculates total verified sales volume collected today.
  double get _todaySalesTotal {
    final now = DateTime.now();
    return _transactionsList
        .where((tx) => tx.isVerified && tx.timestamp.day == now.day && tx.timestamp.month == now.month)
        .fold(0.0, (sum, tx) => sum + (tx.amount ?? 0.0));
  }

  /// Returns total count of verified transactions today.
  int get _todayVerifiedCount {
    final now = DateTime.now();
    return _transactionsList
        .where((tx) => tx.isVerified && tx.timestamp.day == now.day && tx.timestamp.month == now.month)
        .length;
  }

  /// Simulates processing an incoming SMS text alert AND syncs directly to Firestore.
  Future<void> _handleSimulatedSms(String smsText, {String? sourceHeader}) async {
    final user = FirebaseAuth.instance.currentUser;
    print('--------------------------------------------------');
    print('🔍 DEBUG (SMS Trigger): Active User UID = ${user?.uid}');

    if (user == null) {
      print('❌ ERROR: Walang naka-login na user sa Mobile App!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: No active store logged in.')),
      );
      return;
    }

    if (!_isProtectionActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PaymentGuard protection is currently paused.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Process locally with processor
    final processedTx = await _transactionProcessor.processIncomingSms(
      smsText,
      senderHeader: sourceHeader,
      merchantId: user.uid, // 👈 Dynamically pass user.uid
    );

    if (!mounted) return;

    if (processedTx != null) {
      // 🚀 FIRESTORE DIRECT SAVE (Fixes Missing Web Sync Bug)
      try {
        print("🚀 Attempting to save transaction to Firestore...");
        await FirebaseFirestore.instance.collection('transactions').add({
          'store_id': user.uid, // 👈 Store ID binding
          'sender': processedTx.provider.isNotEmpty ? processedTx.provider : sourceHeader ?? 'GCash',
          'sender_name': processedTx.senderName,
          'amount': processedTx.amount ?? 0.0,
          'reference_no': processedTx.refNumber,
          'isScam': processedTx.isScam,
          'status': processedTx.status,
          'message': smsText,
          'timestamp': FieldValue.serverTimestamp(),
        });
        print("✅ SUCCESS: Saved SMS transaction to Firestore for store: ${user.uid}");
      } catch (e) {
        print("❌ FIRESTORE WRITE ERROR (SMS): $e");
      }

      setState(() {
        _transactionsList.insert(0, processedTx);
      });

      String snackbarText;
      Color snackbarColor;

      if (processedTx.isScam) {
        snackbarText = '🚨 SCAM ALERT: Phishing link/threat detected in SMS!';
        snackbarColor = Colors.red.shade900;
      } else if (processedTx.isVerified) {
        final amountDisplay = processedTx.amount != null ? '₱${processedTx.amount!.toStringAsFixed(2)}' : 'Payment';
        snackbarText = '✅ VERIFIED: $amountDisplay from ${processedTx.senderName}';
        snackbarColor = Colors.green.shade800;

        // Automatically trigger TTS voice alert announcing amount and payer name
        _voiceAlert.speakPaymentReceived(
          amount: processedTx.amount,
          senderName: processedTx.senderName,
          refNumber: processedTx.refNumber,
        );
      } else {
        snackbarText = '⚠️ DUPLICATE REJECTED: Ref #${processedTx.refNumber}';
        snackbarColor = Colors.orange.shade900;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            snackbarText,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: snackbarColor,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to parse payment details from SMS string.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// Opens the Camera OCR Receipt Scanner screen AND syncs scan result to Firestore.
  Future<void> _openOcrScanner() async {
    final user = FirebaseAuth.instance.currentUser;

    final ocrResult = await Navigator.push<OcrParsedResult>(
      context,
      MaterialPageRoute(builder: (_) => const OcrScannerScreen()),
    );

    if (ocrResult != null && mounted) {
      final amountDisplay = ocrResult.amount != null ? '₱${ocrResult.amount!.toStringAsFixed(2)}' : 'Payment';
      final bool isMatched = ocrResult.isValid;
      final String statusStr = ocrResult.isScam
          ? 'SCAM_FLAGGED (PHISHING LINK DETECTED)'
          : (isMatched
              ? 'VERIFIED (MATCHED WITH SMS)'
              : 'UNVERIFIED (NO MATCHING SMS / MANUAL CHECK REQUIRED)');

      final scannedTx = TransactionModel(
        id: 'ocr_${DateTime.now().millisecondsSinceEpoch}',
        merchantId: user?.uid ?? 'UNKNOWN_STORE',
        amount: ocrResult.amount,
        refNumber: ocrResult.referenceNo ?? 'NO_REF',
        senderName: ocrResult.sender ?? 'GCash (Scanned)',
        source: ocrResult.walletType,
        timestamp: DateTime.now(),
        status: statusStr,
        sender: ocrResult.walletType,
        message: ocrResult.rawText,
        isScam: ocrResult.isScam,
        threatLevel: ocrResult.threatLevel,
      );

      // 🚀 FIRESTORE DIRECT SAVE FOR OCR RECEIPT
      if (user != null) {
        try {
          await FirebaseFirestore.instance.collection('transactions').add({
            'store_id': user.uid,
            'sender': ocrResult.walletType,
            'sender_name': ocrResult.sender ?? '${ocrResult.walletType} (Scanned)',
            'amount': ocrResult.amount ?? 0.0,
            'reference_no': ocrResult.referenceNo ?? 'NO_REF',
            'isScam': ocrResult.isScam,
            'status': statusStr,
            'message': ocrResult.rawText,
            'timestamp': FieldValue.serverTimestamp(),
          });
          print("✅ SUCCESS: Saved OCR scan transaction to Firestore!");
        } catch (e) {
          print("❌ FIRESTORE WRITE ERROR (OCR): $e");
        }
      }

      setState(() {
        _transactionsList.insert(0, scannedTx);
      });

      if (isMatched) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📸 OCR VERIFIED (MATCHED SMS): $amountDisplay from ${ocrResult.sender}'),
            backgroundColor: Colors.green.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ OCR UNVERIFIED: No matching SMS found for Ref #${ocrResult.referenceNo ?? "N/A"}'),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Displays the Dev SMS Simulator Bottom Sheet for testing.
  void _showDevSimulatorModal() {
    final customSmsController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            top: 24,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bug_report, color: Color(0xFF00E676)),
                  const SizedBox(width: 8),
                  const Text(
                    'SMS Alert Simulator',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Test End-to-End Flow:',
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              
              // 1. Test GCash SMS Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF005CE6), // GCash Blue
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                  label: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Test GCash SMS',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        'Simulates GCash payment (Ref No: 1002...)',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    final random = Random();
                    final String randomRefNo = '1002${random.nextInt(900000) + 100000}';
                    final List<double> realisticAmounts = [50.0, 100.0, 250.0, 500.0, 1000.0, 1500.0];
                    final double randomAmount = realisticAmounts[random.nextInt(realisticAmounts.length)];
                    final String amountStr = randomAmount.toStringAsFixed(2);

                    final String smsPayload =
                        'You have received PHP $amountStr of GCash from JUAN D. 09171234567 with Ref. No. $randomRefNo on ${DateFormat('MM/dd/yyyy').format(DateTime.now())}.';

                    _handleSimulatedSms(smsPayload, sourceHeader: 'GCash');
                  },
                ),
              ),

              const SizedBox(height: 10),

              // 2. Test Maya SMS Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D68F), // Maya Teal Green
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.flash_on, color: Colors.black),
                  label: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Test Maya SMS',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        'Simulates Maya payment (Ref No: 9876...)',
                        style: TextStyle(fontSize: 11, color: Colors.black87),
                      ),
                    ],
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    final random = Random();
                    final String randomRefNo = '9876${random.nextInt(900000) + 100000}';
                    final List<double> realisticAmounts = [50.0, 100.0, 250.0, 500.0, 1000.0, 1500.0];
                    final double randomAmount = realisticAmounts[random.nextInt(realisticAmounts.length)];
                    final String amountStr = randomAmount.toStringAsFixed(2);

                    final String smsPayload =
                        'You received P$amountStr from MARIA CLARA via Maya. Ref No: $randomRefNo on ${DateFormat('MM/dd/yyyy').format(DateTime.now())}.';

                    _handleSimulatedSms(smsPayload, sourceHeader: 'Maya');
                  },
                ),
              ),

              const SizedBox(height: 10),

              // 3. Test MariBank SMS Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5722), // MariBank Orange
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.account_balance, color: Colors.white),
                  label: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Test MariBank SMS',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        'Simulates MariBank transfer (Ref format: MB...)',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    final random = Random();
                    final String randomRefNo = 'MB${random.nextInt(90000000) + 10000000}';
                    final List<double> realisticAmounts = [50.0, 100.0, 250.0, 500.0, 1000.0, 1500.0];
                    final double randomAmount = realisticAmounts[random.nextInt(realisticAmounts.length)];
                    final String amountStr = randomAmount.toStringAsFixed(2);

                    final String smsPayload =
                        'MariBank: You received PHP $amountStr from PEDRO P. via MariBank transfer. Ref No: $randomRefNo.';

                    _handleSimulatedSms(smsPayload, sourceHeader: 'MariBank');
                  },
                ),
              ),

              const SizedBox(height: 10),

              // 4. Test Scam SMS Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.gpp_bad, color: Colors.white),
                  label: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Test Scam SMS (Phishing Alert)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        'Simulates GCash phishing scam link message',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _handleSimulatedSms(
                      'GCash: Your account is LOCKED due to suspicious activity. Verify immediately at http://gcash-security-update.ph',
                      sourceHeader: 'GCash',
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'Other Presets:',
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.flash_on, size: 14, color: Colors.green),
                    label: const Text('Maya (₱500.00)'),
                    onPressed: () {
                      Navigator.pop(context);
                      _handleSimulatedSms(
                        'You received P500.00 from MARIA CLARA via Maya. Ref No: 987654321012.',
                        sourceHeader: 'Maya',
                      );
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.warning, size: 14, color: Colors.orange),
                    label: const Text('Duplicate Ref Check'),
                    onPressed: () {
                      Navigator.pop(context);
                      _handleSimulatedSms(
                        'You have received PHP 500.00 from JUAN D. with Ref No. 1002938475. Balance: PHP 1,250.00',
                        sourceHeader: 'GCash',
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: customSmsController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Or paste custom SMS message here...',
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF00E676)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    final text = customSmsController.text.trim();
                    if (text.isNotEmpty) {
                      Navigator.pop(context);
                      _handleSimulatedSms(text);
                    }
                  },
                  icon: const Icon(Icons.play_arrow, color: Color(0xFF00E676)),
                  label: const Text(
                    'Process Custom SMS',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield, color: Color(0xFF00E676), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseAuth.instance.currentUser != null
                    ? FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).snapshots()
                    : const Stream.empty(),
                builder: (context, snapshot) {
                  final user = FirebaseAuth.instance.currentUser;
                  String storeName = 'PaymentGuard Store';
                  String ownerName = user?.displayName ?? 'Store Owner';

                  if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
                    final data = snapshot.data!.data();
                    if (data != null) {
                      storeName = data['store_name']?.toString() ?? storeName;
                      ownerName = data['owner_name']?.toString() ?? data['full_name']?.toString() ?? ownerName;
                    }
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        storeName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Owner: $ownerName',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined, color: Color(0xFF00E676)),
            tooltip: 'Scan Receipt (OCR)',
            onPressed: _openOcrScanner,
          ),
          IconButton(
            icon: const Icon(Icons.volume_up_outlined),
            tooltip: 'Test Voice Alert',
            onPressed: () => _voiceAlert.speakPaymentReceived(amount: 150.00, senderName: 'JUAN DELA CRUZ'),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            tooltip: 'Logout Store',
            onPressed: () async => await FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'ocr_scanner_fab',
            onPressed: _openOcrScanner,
            backgroundColor: const Color(0xFF00E676),
            foregroundColor: Colors.black,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Scan Receipt (OCR)', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'test_sms_fab',
            onPressed: _showDevSimulatorModal,
            backgroundColor: const Color(0xFF1E293B),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.bug_report, color: Color(0xFF00E676)),
            label: const Text('Simulate Test SMS', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 0. Setup & Permissions Status Checker Banner Card
            _buildSystemStatusCard(),
            const SizedBox(height: 12),

            // 1. Protection Status Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _isProtectionActive
                            ? const Color(0xFF00E676).withValues(alpha: 0.15)
                            : Colors.red.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isProtectionActive ? Icons.verified_user : Icons.gpp_bad,
                        color: _isProtectionActive ? const Color(0xFF00E676) : Colors.red,
                        size: 36,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isProtectionActive
                                ? 'PaymentGuard Protection Active'
                                : 'Protection Paused',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Hive Offline Cache: ${_duplicateChecker.getCachedReferenceCount()} ref numbers',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isProtectionActive,
                      activeThumbColor: const Color(0xFF00E676),
                      onChanged: (val) => setState(() => _isProtectionActive = val),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 2. Today's Sales Summary Cards
            Row(
              children: [
                Expanded(
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.payments, color: Colors.green.shade400, size: 20),
                              const SizedBox(width: 6),
                              const Text('Today\'s Total', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            currencyFormatter.format(_todaySalesTotal),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00E676),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.receipt_long, color: Colors.blue.shade400, size: 20),
                              const SizedBox(width: 6),
                              const Text('Verified Count', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$_todayVerifiedCount Payments',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 3. Recent Transactions Feed Header
            const Text(
              'Recent Counter Payments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (_transactionsList.isEmpty)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(36),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.inbox, size: 48, color: Colors.grey.shade600),
                        const SizedBox(height: 12),
                        const Text(
                          'No payment SMS received yet today.',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap "Simulate Test SMS" below to run live verification.',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _transactionsList.length,
                itemBuilder: (context, index) {
                  final tx = _transactionsList[index];
                  final isVerified = tx.isVerified;
                  final isScam = tx.isScam;

                  final cardBorderColor = isScam
                      ? Colors.red
                      : (isVerified ? Colors.transparent : Colors.orange.withValues(alpha: 0.5));

                  final iconData = isScam
                      ? Icons.gpp_bad
                      : (isVerified ? Icons.check_circle : Icons.warning_amber);

                  final iconColor = isScam
                      ? Colors.red
                      : (isVerified ? Colors.green : Colors.orange);

                  final statusBadgeText = isScam ? 'SCAM_ALERT (HIGH)' : tx.status;
                  final amountDisplay = tx.amount != null ? currencyFormatter.format(tx.amount) : '₱0.00';

                  final providerLabel = tx.provider.isNotEmpty ? tx.provider : tx.source;
                  final String displaySender = (tx.senderName.contains('Scanned') || tx.senderName.toLowerCase().contains(providerLabel.toLowerCase()))
                      ? tx.senderName
                      : '${tx.senderName} ($providerLabel)';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: cardBorderColor, width: isScam ? 1.5 : 1.0),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: iconColor.withValues(alpha: 0.15),
                            child: Icon(iconData, color: iconColor),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  displaySender,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isScam ? Colors.redAccent : Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isScam
                                      ? '⚠️ Phishing Link Alert • ${DateFormat('hh:mm a').format(tx.timestamp)}'
                                      : 'Ref: ${tx.refNumber} • ${DateFormat('hh:mm a').format(tx.timestamp)}',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isScam ? Colors.red.shade200 : Colors.grey.shade400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                amountDisplay,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isVerified ? const Color(0xFF00E676) : Colors.redAccent,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: iconColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  statusBadgeText,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: iconColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// System Status / Permission Checker Banner Card Widget
  Widget _buildSystemStatusCard() {
    if (_isBannerDismissed) return const SizedBox.shrink();

    if (_isCheckingPermissions) {
      return Card(
        elevation: 2,
        color: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E676)),
              ),
              SizedBox(width: 12),
              Text('Checking System Permissions...', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    // Treat Battery Optimization check as ADVISORY/OPTIONAL. SMS & Notification are required.
    final bool requiredPermissionsGranted = _smsGranted && _notificationGranted;

    if (requiredPermissionsGranted) {
      return Card(
        elevation: 2,
        color: const Color(0xFF0F291E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFF00E676).withValues(alpha: 0.5), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.check_circle, color: Color(0xFF00E676), size: 28),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🟢 System Guard Active',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF00E676)),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'SMS listening & notification service fully operational.',
                          style: TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Optional Advisory for Battery Optimization (if not disabled and not dismissed)
              if (!_batteryOptDisabled && !_isBannerDismissed) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.battery_saver, color: Colors.orangeAccent, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Advisory: Set Battery to "Unrestricted" to prevent background sleep.',
                              style: TextStyle(fontSize: 12, color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _dismissBatteryWarning,
                            child: const Text("I've Configured This", style: TextStyle(color: Color(0xFF00E676), fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              await Permission.ignoreBatteryOptimizations.request();
                              _checkPermissions();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Open Settings', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 4,
      color: const Color(0xFF2A1B12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.orangeAccent, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '⚠️ Setup Incomplete: Action Required',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orangeAccent),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  tooltip: "Dismiss Warning / I've Done This",
                  onPressed: _dismissBatteryWarning,
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Grant required permissions to prevent background service interruption by OS.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 16),

            // DETAILED PERMISSION STATUS BREAKDOWN BOX
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                children: [
                  _buildStatusBreakdownRow(
                    icon: Icons.sms,
                    label: '📱 SMS Permission',
                    isGranted: _smsGranted,
                    grantedText: 'Granted',
                    missingText: 'Missing',
                  ),
                  const Divider(color: Color(0xFF334155), height: 16),
                  _buildStatusBreakdownRow(
                    icon: Icons.notifications,
                    label: '🔔 Notification Listener',
                    isGranted: _notificationGranted,
                    grantedText: 'Granted',
                    missingText: 'Missing',
                  ),
                  const Divider(color: Color(0xFF334155), height: 16),
                  _buildStatusBreakdownRow(
                    icon: Icons.battery_saver,
                    label: '🔋 Battery Optimization',
                    isGranted: _batteryOptDisabled,
                    grantedText: 'Ignored (Unrestricted)',
                    missingText: 'Active (Optimized)',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (!_smsGranted) ...[
              _buildPermissionActionRow(
                title: 'SMS Access (Read incoming payment SMS)',
                buttonText: 'Grant SMS Access',
                onPressed: () async {
                  await Permission.sms.request();
                  _checkPermissions();
                },
              ),
              const SizedBox(height: 10),
            ],

            if (!_notificationGranted) ...[
              _buildPermissionActionRow(
                title: 'Notifications (Sound & voice alerts)',
                buttonText: 'Enable Notifications',
                onPressed: () async {
                  await Permission.notification.request();
                  _checkPermissions();
                },
              ),
              const SizedBox(height: 10),
            ],

            if (!_batteryOptDisabled) ...[
              _buildPermissionActionRow(
                title: 'Unrestricted Battery (Prevents background sleep)',
                buttonText: 'Disable Battery Saver',
                onPressed: () async {
                  await Permission.ignoreBatteryOptimizations.request();
                  _checkPermissions();
                },
              ),
              const SizedBox(height: 10),
            ],

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _checkPermissions,
                  icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF00E676)),
                  label: const Text('🔄 Re-check Status', style: TextStyle(color: Color(0xFF00E676), fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                  onPressed: () => openAppSettings(),
                  icon: const Icon(Icons.settings, size: 16, color: Colors.white70),
                  label: const Text('Open System Settings', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBreakdownRow({
    required IconData icon,
    required String label,
    required bool isGranted,
    required String grantedText,
    required String missingText,
  }) {
    final Color badgeColor = isGranted ? const Color(0xFF00E676) : Colors.orangeAccent;
    return Row(
      children: [
        Icon(icon, size: 18, color: badgeColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
          ),
          child: Text(
            isGranted ? grantedText : missingText,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionActionRow({
    required String title,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(buttonText, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}