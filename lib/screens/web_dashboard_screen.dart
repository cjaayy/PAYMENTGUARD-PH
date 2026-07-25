import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../firebase_options.dart';
import '../models/transaction_model.dart';
import '../services/pdf_report_service.dart';
import '../utils/web_audio.dart';
import '../utils/web_download.dart';
import 'customer_counter_screen.dart';

/// Responsive Web Dashboard & Customer Counter Display Screen for Business Owners.
class WebDashboardScreen extends StatefulWidget {
  const WebDashboardScreen({super.key});

  @override
  State<WebDashboardScreen> createState() => _WebDashboardScreenState();
}

class _WebDashboardScreenState extends State<WebDashboardScreen> {
  bool _isCustomerDisplayMode = false;
  bool _isMuted = false;
  String? _lastPlayedTxId;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final currencyFormatter = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

  /// Plays POS success chime sound ("Ding-Dong!") unless audio is explicitly muted.
  void _playChimeSound() {
    if (_isMuted) {
      debugPrint('Audio is muted. Skipping chime.');
      return; // Stop execution if muted
    }
    playChimeSound();
  }

  // Sample fallback mock stream for offline dev/testing when Firestore credentials are not configured yet
  final List<TransactionModel> _fallbackMockTxList = [
    TransactionModel(
      id: 'tx_web_01',
      merchantId: 'STORE_COUNTER_01',
      amount: 150.00,
      refNumber: '102938475610',
      senderName: 'JUAN DELA CRUZ',
      source: 'GCash',
      sender: 'GCash',
      message: 'You have received PHP 150.00 of GCash from JUAN DELA CRUZ.',
      isScam: false,
      threatLevel: 'LOW',
      timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
      status: TransactionStatus.verified.value,
    ),
    TransactionModel(
      id: 'tx_web_02',
      merchantId: 'STORE_COUNTER_01',
      amount: 500.00,
      refNumber: '987654321012',
      senderName: 'MARIA CLARA',
      source: 'Maya',
      sender: 'Maya',
      message: 'You received P500.00 from MARIA CLARA via Maya.',
      isScam: false,
      threatLevel: 'LOW',
      timestamp: DateTime.now().subtract(const Duration(minutes: 18)),
      status: TransactionStatus.verified.value,
    ),
    TransactionModel(
      id: 'tx_web_03',
      merchantId: 'STORE_COUNTER_01',
      amount: null,
      refNumber: 'NO_REF',
      senderName: 'PHISHING SENDER',
      source: 'GCash',
      sender: 'GCash',
      message: 'GCash: Your account is LOCKED due to suspicious activity. Verify immediately at http://gcash-security-update.ph',
      isScam: true,
      threatLevel: 'HIGH',
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      status: 'SCAM_FLAGGED',
    ),
  ];

  /// Process, filter, deduplicate, and sort transactions.
  /// ALWAYS allows scam/phishing alerts regardless of reference_no.
  List<TransactionModel> _processAndDeduplicateTransactions(List<TransactionModel> rawList) {
    // 1. Filter: ALWAYS allow scam alerts; for legitimate payments, require valid reference number
    final validTxList = rawList.where((tx) {
      if (tx.isScam) return true; // ALWAYS allow scam alerts regardless of reference number!
      final ref = tx.refNumber.trim().toUpperCase();
      return ref.isNotEmpty && ref != 'NO_REF' && ref != 'N/A' && ref != 'NULL';
    }).toList();

    // 2. Deduplicate: Non-scam documents by refNumber; Scam documents by unique ID so phishing alerts are never merged
    final Map<String, TransactionModel> uniqueMap = {};
    for (final tx in validTxList) {
      if (tx.isScam) {
        final key = 'scam_${tx.id.isNotEmpty ? tx.id : tx.timestamp.millisecondsSinceEpoch}';
        uniqueMap[key] = tx;
      } else {
        final key = tx.refNumber.trim().toUpperCase();
        if (!uniqueMap.containsKey(key)) {
          uniqueMap[key] = tx;
        } else {
          final existing = uniqueMap[key]!;
          if (!existing.isVerified && tx.isVerified) {
            uniqueMap[key] = tx;
          } else if (tx.timestamp.isAfter(existing.timestamp)) {
            uniqueMap[key] = tx;
          }
        }
      }
    }

    // 3. Sort descending by latest timestamp
    final List<TransactionModel> deduplicatedList = uniqueMap.values.toList();
    deduplicatedList.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return deduplicatedList;
  }

  /// Safe Firestore stream builder filtered by active store_id.
  Stream<List<TransactionModel>> _getTransactionsStream() {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('WEB_AUTH_UID: $currentUserId');
    print('WEB_AUTH_UID: $currentUserId');

    final baseCollection = FirebaseFirestore.instance.collection('transactions');
    Query<Map<String, dynamic>> query;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      query = baseCollection.where('store_id', isEqualTo: currentUserId).orderBy('timestamp', descending: true);
    } else {
      query = baseCollection.orderBy('timestamp', descending: true);
    }

    return query.snapshots().map((snapshot) {
      debugPrint('[WebDashboard] Stream updated: ${snapshot.docs.length} raw documents for store_id: $currentUserId');
      if (snapshot.docs.isEmpty) return _processAndDeduplicateTransactions(_fallbackMockTxList);
      final rawList = snapshot.docs.map((doc) => TransactionModel.fromFirestore(doc)).toList();
      return _processAndDeduplicateTransactions(rawList);
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? webUid = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('WEB_AUTH_UID: $webUid');

    return StreamBuilder<List<TransactionModel>>(
      stream: _getTransactionsStream(),
      builder: (context, snapshot) {
        // 1. STREAM ERROR VISIBILITY UI HANDLING
        if (snapshot.hasError) {
          final errorObj = snapshot.error;
          debugPrint('[WebDashboardScreen] Firestore Stream Error: $errorObj');
          print('WEB_STREAM_ERROR: $errorObj');

          return Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            appBar: AppBar(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('PaymentGuard PH - Stream Debug View'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () async => await FirebaseAuth.instance.signOut(),
                ),
              ],
            ),
            body: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 700),
                padding: const EdgeInsets.all(32),
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.red.shade400, width: 2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                    const SizedBox(height: 16),
                    const Text(
                      'FIRESTORE STREAM ERROR DETECTED',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.redAccent),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'WEB_AUTH_UID: ${webUid ?? "NULL / NOT LOGGED IN"}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      '$errorObj',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red.shade200, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry Real-time Stream Query'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final rawTransactions = snapshot.data ?? _fallbackMockTxList;
        final transactions = _processAndDeduplicateTransactions(rawTransactions);

        // Trigger POS Success Audio Chime ("Ding-Dong!") on New Legitimate Transaction Arrival
        if (transactions.isNotEmpty) {
          final latestTx = transactions.first;
          if (_lastPlayedTxId != null && _lastPlayedTxId != latestTx.id && !latestTx.isScam) {
            _playChimeSound();
          }
          _lastPlayedTxId = latestTx.id;
        }

        // Apply Search Filter
        final filteredTransactions = transactions.where((tx) {
          if (_searchQuery.trim().isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return tx.refNumber.toLowerCase().contains(q) ||
              tx.senderName.toLowerCase().contains(q) ||
              tx.source.toLowerCase().contains(q);
        }).toList();

        // Customer Display Mode Fullscreen
        if (_isCustomerDisplayMode) {
          return CustomerCounterView(
            onExitCounterMode: () => setState(() => _isCustomerDisplayMode = false),
          );
        }

        // Owner Dashboard View
        return _buildOwnerDashboardView(transactions, filteredTransactions);
      },
    );
  }

  // ===========================================================================
  // CUSTOMER COUNTER DISPLAY VIEW
  // ===========================================================================

  Widget _buildCustomerCounterView(TransactionModel? latestTx) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _isCustomerDisplayMode = false),
            icon: const Icon(Icons.dashboard, color: Colors.white70),
            label: const Text('Exit Counter Mode', style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 750),
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E676).withValues(alpha: 0.12),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
              border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4), width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified, size: 88, color: Color(0xFF00E676)),
                ),
                const SizedBox(height: 24),
                const Text(
                  'PAYMENT CONFIRMED',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: Color(0xFF00E676),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Thank you! Your payment has been verified instantly.',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade300),
                ),
                const Divider(height: 48, thickness: 1),
                if (latestTx != null && latestTx.isVerified) ...[
                  Text(
                    currencyFormatter.format(latestTx.amount),
                    style: const TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Payer: ${latestTx.senderName}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ref No: ${latestTx.refNumber} (${latestTx.source})',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ),
                ] else
                  const Text('Waiting for incoming counter payment...'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  Map<String, String> formatCsvDateTime(dynamic rawTimestamp) {
    if (rawTimestamp == null) return {'date': '"N/A"', 'time': '"N/A"'};

    DateTime dt;
    if (rawTimestamp is Timestamp) {
      dt = rawTimestamp.toDate();
    } else if (rawTimestamp is DateTime) {
      dt = rawTimestamp;
    } else if (rawTimestamp is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(rawTimestamp);
    } else {
      dt = DateTime.tryParse(rawTimestamp.toString()) ?? DateTime.now();
    }

    String year = dt.year.toString();
    String month = dt.month.toString().padLeft(2, '0');
    String day = dt.day.toString().padLeft(2, '0');

    int hourInt = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    String hour = hourInt.toString().padLeft(2, '0');
    String minute = dt.minute.toString().padLeft(2, '0');
    String period = dt.hour >= 12 ? 'PM' : 'AM';

    // Wrapping in `="VALUE"` forces Excel to render as short plain text strings
    String dateStr = '="$year-$month-$day"';
    String timeStr = '="$hour:$minute $period"';

    return {'date': dateStr, 'time': timeStr};
  }

  String _formattedCsvRef(String rawRef) {
    final String trimmed = rawRef.trim();
    if (trimmed.isEmpty || trimmed == 'NO_REF' || trimmed == 'N/A' || trimmed == 'NULL') {
      return '"$trimmed"';
    }
    // Wrapping with `="VALUE"` forces Excel & Google Sheets to treat it as exact plain text
    return '="$trimmed"';
  }

  void _exportTransactionsCsv(List<TransactionModel> transactions) {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('Date,Time,E-Wallet Source,Sender Name,Amount (PHP),Reference Number,Status');

    for (final tx in transactions) {
      final dateTimeMap = formatCsvDateTime(tx.timestamp);
      final String dateCol = dateTimeMap['date']!;
      final String timeCol = dateTimeMap['time']!;

      final String source = _escapeCsv(tx.provider.isNotEmpty ? tx.provider : tx.source);
      final String sender = _escapeCsv(tx.senderName.isNotEmpty ? tx.senderName : 'N/A');
      final String amountStr = tx.amount != null ? tx.amount!.toStringAsFixed(2) : '0.00';
      final String rawRef = tx.refNumber.trim().isNotEmpty ? tx.refNumber.trim() : 'NO_REF';
      final String refNo = _formattedCsvRef(rawRef);

      String statusStr = 'VERIFIED';
      if (tx.isScam) {
        statusStr = 'PHISHING_SCAM_FLAGGED';
      } else if (tx.isDuplicate) {
        statusStr = 'DUPLICATE_REJECTED';
      }

      buffer.writeln('$dateCol,$timeCol,$source,$sender,$amountStr,$refNo,$statusStr');
    }

    final String todayDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final String filename = 'PaymentGuard_Log_$todayDateStr.csv';

    downloadFile(buffer.toString(), filename);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ CSV Log Exported successfully ($filename)'),
          backgroundColor: const Color(0xFF00E676),
        ),
      );
    }
  }

  Future<void> _exportTransactionsPdf(
    List<TransactionModel> transactions,
    String storeName,
    String ownerName,
  ) async {
    try {
      final pdfBytes = await PdfReportService.generateDailyPdfReport(
        transactions: transactions,
        storeName: storeName,
        ownerName: ownerName,
      );

      final String todayDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final String filename = 'PaymentGuard_Report_$todayDateStr.pdf';

      try {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
          name: filename,
        );
      } catch (printErr) {
        // Fallback to direct web download if Printing plugin is unavailable
        downloadBytes(pdfBytes, filename);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ PDF Sales Report generated ($filename)'),
            backgroundColor: const Color(0xFF00E676),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showQrSettingsDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await showDialog(
      context: context,
      builder: (context) {
        return _QrUploadDialog(userId: user.uid);
      },
    );
  }

  String _escapeCsv(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      final escaped = field.replaceAll('"', '""');
      return '"$escaped"';
    }
    return field;
  }

  // ===========================================================================
  // OWNER DASHBOARD VIEW
  // ===========================================================================

  Widget _buildOwnerDashboardView(
    List<TransactionModel> allTransactions,
    List<TransactionModel> filteredTransactions,
  ) {
    final todayTxList = allTransactions.where((t) => _isToday(t.timestamp)).toList();
    final todayRevenue = todayTxList
        .where((t) => !t.isScam)
        .fold(0.0, (previousValue, element) => previousValue + (element.amount ?? 0.0));
    final todayVerifiedCount = todayTxList.where((t) => !t.isScam).length;
    final todayScamsBlocked = todayTxList.where((t) => t.isScam).length;

    String currentStoreName = 'PaymentGuard Store';
    String currentOwnerName = FirebaseAuth.instance.currentUser?.displayName ?? 'Store Owner';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Icon(Icons.shield, color: Color(0xFF00E676), size: 28),
              const SizedBox(width: 10),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
                      currentStoreName = storeName;
                      currentOwnerName = ownerName;
                    }
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        storeName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
                      ),
                      Text(
                        'Owner: $ownerName',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.w600),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.fiber_manual_record, color: Colors.green, size: 8),
                    SizedBox(width: 4),
                    Text('Real-time Stream', style: TextStyle(fontSize: 10, color: Colors.green)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isMuted ? Icons.volume_off : Icons.volume_up,
              color: _isMuted ? Colors.white54 : const Color(0xFF00E676),
            ),
            tooltip: _isMuted ? 'Unmute Sound' : 'Mute Sound',
            onPressed: () {
              setState(() {
                _isMuted = !_isMuted;
              });
            },
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.lightBlueAccent,
              side: const BorderSide(color: Colors.lightBlueAccent, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _showQrSettingsDialog,
            icon: const Icon(Icons.qr_code, size: 18),
            label: const Text('QR Settings', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: const Color(0xFF00E676),
              side: const BorderSide(color: Color(0xFF00E676), width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _exportTransactionsCsv(allTransactions),
            icon: const Icon(Icons.table_chart, size: 18),
            label: const Text('Export CSV', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _exportTransactionsPdf(allTransactions, currentStoreName, currentOwnerName),
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text('Export PDF Report', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => setState(() => _isCustomerDisplayMode = true),
            icon: const Icon(Icons.desktop_windows),
            label: const Text('Customer Counter View', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            tooltip: 'Logout Store',
            onPressed: () async => await FirebaseAuth.instance.signOut(),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Metrics Bar (Responsive Layout)
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 700;
                if (isNarrow) {
                  return Column(
                    children: [
                      _buildMetricCard(
                        title: 'Total Revenue Today',
                        value: currencyFormatter.format(todayRevenue),
                        icon: Icons.account_balance_wallet,
                        color: const Color(0xFF00E676),
                      ),
                      const SizedBox(height: 12),
                      _buildMetricCard(
                        title: 'Total Transactions',
                        value: '$todayVerifiedCount Orders',
                        icon: Icons.receipt_long,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(height: 12),
                      _buildMetricCard(
                        title: 'Scam Attempts Blocked',
                        value: '$todayScamsBlocked Attempted',
                        icon: Icons.security,
                        color: Colors.redAccent,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Total Revenue Today',
                        value: currencyFormatter.format(todayRevenue),
                        icon: Icons.account_balance_wallet,
                        color: const Color(0xFF00E676),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Total Transactions',
                        value: '$todayVerifiedCount Orders',
                        icon: Icons.receipt_long,
                        color: Colors.blueAccent,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Scam Attempts Blocked',
                        value: '$todayScamsBlocked Attempted',
                        icon: Icons.security,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 28),

            // Search & Filter Bar
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search by Reference Number, Sender Name, or Source...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Real-Time Transaction Table
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Live Firestore Payment Stream',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Chip(
                          label: Text('${filteredTransactions.length} Records'),
                          backgroundColor: const Color(0xFF0F172A),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    if (filteredTransactions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'No matching payment records found.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredTransactions.length,
                        separatorBuilder: (context, index) => const Divider(height: 12),
                        itemBuilder: (context, index) {
                          final tx = filteredTransactions[index];
                          final isVerified = tx.isVerified;
                          final isScam = tx.isScam;
                          final threatLevel = tx.threatLevel.toUpperCase();

                          final iconColor = isScam
                              ? Colors.red
                              : (isVerified ? Colors.green : Colors.orange);
                          final iconData = isScam
                              ? Icons.gpp_bad
                              : (isVerified ? Icons.check_circle_outline : Icons.warning_amber);

                          final amountDisplay = tx.amount != null ? currencyFormatter.format(tx.amount) : 'N/A';

                          // 3. SAFE SENDER DISPLAY EXTRACTION
                          final String displaySender = tx.senderName.trim().isNotEmpty
                              ? tx.senderName
                              : (tx.sender.trim().isNotEmpty ? tx.sender : 'Unknown Sender');

                          // 4. PROMINENT RED PHISHING SCAM ALERT CARD UI
                          if (isScam) {
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.red.shade900.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.red.shade400, width: 2.0),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.red.withValues(alpha: 0.25),
                                    child: const Icon(Icons.gpp_bad, color: Colors.redAccent),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade900,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                '🚨 PHISHING ALERT DETECTED',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.red, width: 0.8),
                                              ),
                                              child: Text(
                                                'THREAT: $threatLevel',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.redAccent,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Sender: $displaySender (${tx.provider.isNotEmpty ? tx.provider : tx.source})',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Time: ${DateFormat('MMM dd, yyyy - hh:mm a').format(tx.timestamp)}',
                                          style: TextStyle(fontSize: 12, color: Colors.red.shade200),
                                        ),
                                        if (tx.message.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF0F172A),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.red.shade900),
                                            ),
                                            child: Text(
                                              'Payload Message: "${tx.message}"',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.white70,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          // Standard Verified / Pending Payment Card
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            leading: CircleAvatar(
                              backgroundColor: iconColor.withValues(alpha: 0.15),
                              child: Icon(iconData, color: iconColor),
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displaySender,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    tx.sender.isNotEmpty ? tx.sender : tx.source,
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 2),
                                Text(
                                  'Ref No: ${tx.refNumber} • ${DateFormat('MMM dd, yyyy - hh:mm a').format(tx.timestamp)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                                if (tx.message.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'SMS: "${tx.message}"',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade500),
                                  ),
                                ],
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  amountDisplay,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isVerified ? const Color(0xFF00E676) : Colors.redAccent,
                                  ),
                                ),
                                Text(
                                  tx.status,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: iconColor,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// STORE QR CODE DIRECT FILE UPLOAD MODAL
// =============================================================================

class _QrUploadDialog extends StatefulWidget {
  final String userId;
  const _QrUploadDialog({required this.userId});

  @override
  State<_QrUploadDialog> createState() => _QrUploadDialogState();
}

class _QrUploadDialogState extends State<_QrUploadDialog> {
  bool _isLoading = true;
  bool _isUploadingGcash = false;
  bool _isUploadingMaya = false;
  bool _isUploadingMaribank = false;
  String? _gcashData;
  String? _mayaData;
  String? _maribankData;

  @override
  void initState() {
    super.initState();
    _fetchCurrentUrls();
  }

  Future<void> _ensureFirebaseInitialized() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    } catch (e) {
      debugPrint('Firebase init check error: $e');
    }
  }

  Future<void> _fetchCurrentUrls() async {
    await _ensureFirebaseInitialized();
    if (Firebase.apps.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _gcashData = data['gcash_qr_base64']?.toString().trim() ?? data['gcash_qr_url']?.toString().trim();
        _mayaData = data['maya_qr_base64']?.toString().trim() ?? data['maya_qr_url']?.toString().trim();
        _maribankData = data['maribank_qr_base64']?.toString().trim() ?? data['maribank_qr_url']?.toString().trim();

        if (_gcashData != null && _gcashData!.isEmpty) _gcashData = null;
        if (_mayaData != null && _mayaData!.isEmpty) _mayaData = null;
        if (_maribankData != null && _maribankData!.isEmpty) _maribankData = null;
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _uploadQrAsBase64(String providerKey, [String? userIdParam]) async {
    await _ensureFirebaseInitialized();
    if (Firebase.apps.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Firebase is not initialized. Please refresh the page.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Safely fallback to current logged-in Auth User ID
    final String targetUserId = (userIdParam != null && userIdParam.isNotEmpty)
        ? userIdParam
        : (widget.userId.isNotEmpty ? widget.userId : (FirebaseAuth.instance.currentUser?.uid ?? ''));

    if (targetUserId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: User not logged in. Please re-login.')),
        );
      }
      return;
    }

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, // Required for Web & Mobile to obtain file bytes
      );

      if (result == null || result.files.isEmpty || result.files.single.bytes == null) {
        return;
      }

      final Uint8List fileBytes = result.files.single.bytes!;

      setState(() {
        if (providerKey == 'gcash') _isUploadingGcash = true;
        if (providerKey == 'maya') _isUploadingMaya = true;
        if (providerKey == 'maribank') _isUploadingMaribank = true;
      });

      // Convert raw image bytes to Base64 String (Zero Firebase Storage dependency!)
      final String base64Image = base64Encode(fileBytes);

      // Save directly in Firestore user profile
      await FirebaseFirestore.instance.collection('users').doc(targetUserId).set({
        '${providerKey}_qr_base64': base64Image,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          if (providerKey == 'gcash') _gcashData = base64Image;
          if (providerKey == 'maya') _mayaData = base64Image;
          if (providerKey == 'maribank') _maribankData = base64Image;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${providerKey.toUpperCase()} QR code saved successfully!'),
            backgroundColor: const Color(0xFF00E676),
          ),
        );
      }
    } catch (e) {
      debugPrint("Base64 Save Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save QR: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (providerKey == 'gcash') _isUploadingGcash = false;
          if (providerKey == 'maya') _isUploadingMaya = false;
          if (providerKey == 'maribank') _isUploadingMaribank = false;
        });
      }
    }
  }

  Future<void> _removeQrImage(String providerKey) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.userId).set({
        '${providerKey}_qr_base64': FieldValue.delete(),
        '${providerKey}_qr_url': FieldValue.delete(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          if (providerKey == 'gcash') _gcashData = null;
          if (providerKey == 'maya') _mayaData = null;
          if (providerKey == 'maribank') _maribankData = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🗑️ ${providerKey.toUpperCase()} QR Code removed'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing QR image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(
        children: [
          Icon(Icons.qr_code_2, color: Color(0xFF00E676), size: 28),
          SizedBox(width: 10),
          Text('Store QR Code Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 200,
              width: 480,
              child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
            )
          : SingleChildScrollView(
              child: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Upload store QR codes for GCash, Maya, and MariBank. Images are stored safely as Base64 strings directly in Firestore (No paid cloud storage required!).',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 24),

                    // 1. GCash QR Code Upload Section
                    _buildUploadCard(
                      providerTitle: 'GCash QR Code',
                      brandColor: const Color(0xFF005CE6),
                      qrData: _gcashData,
                      isUploading: _isUploadingGcash,
                      onUploadPressed: () => _uploadQrAsBase64('gcash'),
                      onRemovePressed: () => _removeQrImage('gcash'),
                    ),
                    const SizedBox(height: 16),

                    // 2. Maya QR Code Upload Section
                    _buildUploadCard(
                      providerTitle: 'Maya QR Code',
                      brandColor: const Color(0xFF00D68F),
                      qrData: _mayaData,
                      isUploading: _isUploadingMaya,
                      onUploadPressed: () => _uploadQrAsBase64('maya'),
                      onRemovePressed: () => _removeQrImage('maya'),
                    ),
                    const SizedBox(height: 16),

                    // 3. MariBank QR Code Upload Section
                    _buildUploadCard(
                      providerTitle: 'MariBank QR Code',
                      brandColor: const Color(0xFFFF5722),
                      qrData: _maribankData,
                      isUploading: _isUploadingMaribank,
                      onUploadPressed: () => _uploadQrAsBase64('maribank'),
                      onRemovePressed: () => _removeQrImage('maribank'),
                    ),
                  ],
                ),
              ),
            ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E676),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildUploadCard({
    required String providerTitle,
    required Color brandColor,
    required String? qrData,
    required bool isUploading,
    required VoidCallback onUploadPressed,
    required VoidCallback onRemovePressed,
  }) {
    final bool hasImage = qrData != null && qrData.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brandColor.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        children: [
          // Preview Thumbnail (Renders Base64 or URL)
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: brandColor),
            ),
            child: isUploading
                ? Center(child: CircularProgressIndicator(color: brandColor, strokeWidth: 2))
                : hasImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _buildQrThumbnail(qrData!),
                      )
                    : const Icon(Icons.qr_code, size: 40, color: Colors.grey),
          ),
          const SizedBox(width: 16),
          // Details & Actions
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  providerTitle,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: brandColor),
                ),
                const SizedBox(height: 4),
                Text(
                  hasImage ? '✅ Active on Customer View' : 'No QR uploaded yet',
                  style: TextStyle(fontSize: 12, color: hasImage ? Colors.greenAccent : Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandColor.withValues(alpha: 0.2),
                        foregroundColor: brandColor,
                        side: BorderSide(color: brandColor),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: isUploading ? null : onUploadPressed,
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: Text(hasImage ? 'Replace Image' : 'Upload QR Image', style: const TextStyle(fontSize: 12)),
                    ),
                    if (hasImage && !isUploading) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        tooltip: 'Remove QR Image',
                        onPressed: onRemovePressed,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrThumbnail(String qrData) {
    if (qrData.startsWith('http://') || qrData.startsWith('https://')) {
      return Image.network(
        qrData,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
      );
    }

    try {
      String cleanBase64 = qrData;
      if (cleanBase64.contains(',')) {
        cleanBase64 = cleanBase64.split(',').last;
      }
      final bytes = base64Decode(cleanBase64);
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
      );
    } catch (_) {
      return const Icon(Icons.broken_image, color: Colors.grey);
    }
  }
}
