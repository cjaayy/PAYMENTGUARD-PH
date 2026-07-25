import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../models/transaction_model.dart';
import '../services/duplicate_checker_service.dart';
import '../services/transaction_processor.dart';
import '../services/voice_alert_service.dart';

/// Mobile Home Screen designed for store cashiers using an Android phone at the counter.
class MobileHomeScreen extends ConsumerStatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  ConsumerState<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends ConsumerState<MobileHomeScreen> {
  bool _isProtectionActive = true;
  late DuplicateCheckerService _duplicateChecker;
  late VoiceAlertService _voiceAlert;
  late TransactionProcessor _transactionProcessor;
  
  final List<TransactionModel> _transactionsList = [];
  final currencyFormatter = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

  @override
  void initState() {
    super.initState();
    _initServices();
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

  /// Simulates processing an incoming SMS text alert.
  Future<void> _handleSimulatedSms(String smsText, {String? sourceHeader}) async {
    if (!_isProtectionActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PaymentGuard protection is currently paused.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final processedTx = await _transactionProcessor.processIncomingSms(
      smsText,
      senderHeader: sourceHeader,
      merchantId: 'STORE_COUNTER_01',
    );

    if (!mounted) return;

    if (processedTx != null) {
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
              
              // 1. Test Legit SMS Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.check_circle_outline, color: Colors.black),
                  label: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Test Legit SMS (GCash ₱500.00)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        'Simulates valid GCash payment from JUAN D.',
                        style: TextStyle(fontSize: 11, color: Colors.black87),
                      ),
                    ],
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _handleSimulatedSms(
                      'You have received PHP 500.00 from JUAN D. with Ref No. 1002938475. Balance: PHP 1,250.00',
                      sourceHeader: 'GCash',
                    );
                  },
                ),
              ),

              const SizedBox(height: 10),

              // 2. Test Scam SMS Button
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
            const Text(
              'PaymentGuard Cashier',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up_outlined),
            tooltip: 'Test Tagalog Voice',
            onPressed: () => _voiceAlert.speakPaymentReceived(amount: 150.00, senderName: 'JUAN DELA CRUZ'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showDevSimulatorModal,
        backgroundColor: const Color(0xFF00E676),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.bug_report),
        label: const Text('Simulate Test SMS', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: cardBorderColor, width: isScam ? 1.5 : 1.0),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: CircleAvatar(
                        backgroundColor: iconColor.withValues(alpha: 0.15),
                        child: Icon(iconData, color: iconColor),
                      ),
                      title: Text(
                        '${tx.senderName} (${tx.source})',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isScam ? Colors.redAccent : Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        isScam
                            ? '⚠️ Phishing Link Alert • ${DateFormat('hh:mm a').format(tx.timestamp)}'
                            : 'Ref: ${tx.refNumber} • ${DateFormat('hh:mm a').format(tx.timestamp)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isScam ? Colors.red.shade200 : Colors.grey.shade400,
                        ),
                      ),
                      trailing: Column(
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
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
