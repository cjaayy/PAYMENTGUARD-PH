import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/transaction_model.dart';

/// Responsive Web Dashboard & Customer Counter Display Screen for Business Owners.
class WebDashboardScreen extends StatefulWidget {
  const WebDashboardScreen({super.key});

  @override
  State<WebDashboardScreen> createState() => _WebDashboardScreenState();
}

class _WebDashboardScreenState extends State<WebDashboardScreen> {
  bool _isCustomerDisplayMode = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final currencyFormatter = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

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

  /// Safe Firestore stream builder that falls back to mock data if Firestore is uninitialized or empty.
  Stream<List<TransactionModel>> _getTransactionsStream() {
    try {
      return FirebaseFirestore.instance
          .collection('transactions')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((snapshot) {
        if (snapshot.docs.isEmpty) return _fallbackMockTxList;
        return snapshot.docs.map((doc) => TransactionModel.fromFirestore(doc)).toList();
      });
    } catch (_) {
      // Fallback Stream for dev mode
      return Stream.value(_fallbackMockTxList);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TransactionModel>>(
      stream: _getTransactionsStream(),
      builder: (context, snapshot) {
        final transactions = snapshot.data ?? _fallbackMockTxList;

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
          return _buildCustomerCounterView(transactions.firstOrNull);
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

  // ===========================================================================
  // OWNER DASHBOARD VIEW
  // ===========================================================================

  Widget _buildOwnerDashboardView(
    List<TransactionModel> allTransactions,
    List<TransactionModel> filteredTransactions,
  ) {
    final verifiedTxList = allTransactions.where((t) => t.isVerified);
    final totalDailyVolume = verifiedTxList.fold(0.0, (previousValue, element) => previousValue + (element.amount ?? 0.0));
    final totalVerifiedCount = verifiedTxList.length;
    final totalBlockedDuplicates = allTransactions.where((t) => t.isDuplicate).length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Icon(Icons.shield, color: Color(0xFF00E676), size: 28),
              const SizedBox(width: 10),
              const Text(
                'PaymentGuard PH Owner',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                        title: 'Total Sales Volume Today',
                        value: currencyFormatter.format(totalDailyVolume),
                        icon: Icons.account_balance_wallet,
                        color: const Color(0xFF00E676),
                      ),
                      const SizedBox(height: 12),
                      _buildMetricCard(
                        title: 'Verified Transactions',
                        value: '$totalVerifiedCount Payments',
                        icon: Icons.check_circle,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(height: 12),
                      _buildMetricCard(
                        title: 'Duplicate Scams Blocked',
                        value: '$totalBlockedDuplicates Attempted',
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
                        title: 'Total Sales Volume Today',
                        value: currencyFormatter.format(totalDailyVolume),
                        icon: Icons.account_balance_wallet,
                        color: const Color(0xFF00E676),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Verified Transactions',
                        value: '$totalVerifiedCount Payments',
                        icon: Icons.check_circle,
                        color: Colors.blueAccent,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Duplicate Scams Blocked',
                        value: '$totalBlockedDuplicates Attempted',
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

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            leading: CircleAvatar(
                              backgroundColor: iconColor.withValues(alpha: 0.15),
                              child: Icon(iconData, color: iconColor),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  tx.senderName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isScam ? Colors.redAccent : Colors.white,
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
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isScam ? Colors.red.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isScam ? Colors.red : Colors.green,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    'THREAT: $threatLevel',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isScam ? Colors.redAccent : Colors.greenAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 2),
                                Text(
                                  isScam
                                      ? '⚠️ Phishing Link Alert • ${DateFormat('MMM dd, yyyy - hh:mm a').format(tx.timestamp)}'
                                      : 'Ref No: ${tx.refNumber} • ${DateFormat('MMM dd, yyyy - hh:mm a').format(tx.timestamp)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isScam ? Colors.red.shade200 : Colors.grey.shade400,
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
                                  isScam ? 'SCAM_FLAGGED' : tx.status,
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
