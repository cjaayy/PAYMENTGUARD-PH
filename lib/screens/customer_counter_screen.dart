import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';

/// Customer Counter View Screen showing real-time payment status for store customers.
/// Automatically transitions between "Waiting for Payment..." Idle State and
/// large GREEN "PAYMENT CONFIRMED!" banner state for 15 seconds.
class CustomerCounterView extends StatefulWidget {
  final VoidCallback? onExitCounterMode;

  const CustomerCounterView({
    super.key,
    this.onExitCounterMode,
  });

  @override
  State<CustomerCounterView> createState() => _CustomerCounterViewState();
}

class _CustomerCounterViewState extends State<CustomerCounterView> {
  Timer? _resetTimer;
  TransactionModel? _currentPayment;
  String? _lastProcessedTxId;

  final currencyFormatter = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  /// Listens for new non-scam transactions and manages 2-second auto-reset timer to Idle state.
  void _processIncomingTransaction(TransactionModel? latestTx) {
    if (latestTx == null) return;
    if (latestTx.id == _lastProcessedTxId) return;

    final diffInSeconds = DateTime.now().difference(latestTx.timestamp).inSeconds;

    // Only process recent transactions (created within last 15s)
    if (diffInSeconds >= 0 && diffInSeconds <= 15) {
      _lastProcessedTxId = latestTx.id;
      _currentPayment = latestTx;

      _resetTimer?.cancel();

      // Duplicate warning displayed for 3 seconds; Verified payment displayed for 2 seconds.
      final int displaySeconds = (latestTx.isDuplicate || latestTx.status == TransactionStatus.duplicateRejected.value) ? 3 : 2;

      _resetTimer = Timer(Duration(seconds: displaySeconds), () {
        if (mounted) {
          setState(() {
            _currentPayment = null; // Auto-resets screen back to Idle
          });
        }
      });
    }
  }

  /// Stream builder that strictly EXCLUDES phishing/scam alerts from Counter View.
  Stream<TransactionModel?> _getLatestTransactionStream() {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    try {
      final baseCollection = FirebaseFirestore.instance.collection('transactions');
      Query<Map<String, dynamic>> query;
      if (currentUserId != null && currentUserId.isNotEmpty) {
        query = baseCollection.where('store_id', isEqualTo: currentUserId).orderBy('timestamp', descending: true).limit(10);
      } else {
        query = baseCollection.orderBy('timestamp', descending: true).limit(10);
      }

      return query.snapshots().map((snapshot) {
        if (snapshot.docs.isEmpty) return null;

        // 1. EXCLUDE PHISHING / SCAM ALERTS FROM COUNTER VIEW
        final nonScamDocs = snapshot.docs.where((doc) {
          final data = doc.data();
          final bool isScam = (data['isScam'] == true) || (data['is_scam'] == true);
          return !isScam;
        }).toList();

        if (nonScamDocs.isEmpty) return null;

        final doc = nonScamDocs.first;
        final data = doc.data();
        final String rawRef = (data['reference_no'] as String?) ??
            (data['refNumber'] as String?) ??
            (data['ref_number'] as String?) ??
            (data['ref_no'] as String?) ??
            '';

        final model = TransactionModel.fromFirestore(doc);
        if (model.refNumber.isEmpty && rawRef.isNotEmpty) {
          return model.copyWith(refNumber: rawRef);
        }
        return model;
      });
    } catch (_) {
      return Stream.value(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (widget.onExitCounterMode != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton.icon(
                onPressed: widget.onExitCounterMode,
                icon: const Icon(Icons.dashboard, color: Colors.white70),
                label: const Text('Exit Counter Mode', style: TextStyle(color: Colors.white70)),
              ),
            ),
        ],
      ),
      body: StreamBuilder<TransactionModel?>(
        stream: _getLatestTransactionStream(),
        builder: (context, snapshot) {
          final latestTx = snapshot.data;
          _processIncomingTransaction(latestTx);

          Widget activeView;
          if (_currentPayment != null) {
            if (_currentPayment!.isDuplicate || _currentPayment!.status == TransactionStatus.duplicateRejected.value) {
              activeView = _buildDuplicateWarningState(_currentPayment!);
            } else {
              activeView = _buildConfirmedBannerState(_currentPayment!);
            }
          } else {
            activeView = _buildIdleWaitingState();
          }

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: activeView,
          );
        },
      ),
    );
  }

  /// 1. DEFAULT IDLE STATE: "Waiting for Payment..."
  Widget _buildIdleWaitingState() {
    return Center(
      key: const ValueKey('idle_state'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: const Color(0xFF334155), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulse/Listening Animation Indicator
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF00E676).withValues(alpha: 0.08),
                    ),
                  ),
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF00E676).withValues(alpha: 0.15),
                    ),
                  ),
                  const Icon(Icons.qr_code_scanner, size: 56, color: Color(0xFF00E676)),
                ],
              ),
              const SizedBox(height: 32),
              const Text(
                'Waiting for Payment...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Scan QR Code to pay via GCash, Maya, or MariBank',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 36),
              const Divider(color: Color(0xFF334155)),
              const SizedBox(height: 24),
              // Supported Providers Badges
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildProviderBadge('GCash', const Color(0xFF005CE6)),
                  const SizedBox(width: 12),
                  _buildProviderBadge('Maya', const Color(0xFF00D68F)),
                  const SizedBox(width: 12),
                  _buildProviderBadge('MariBank', const Color(0xFFFF5722)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 2. TRANSACTION CONFIRMED STATE: Large GREEN "PAYMENT CONFIRMED!" Banner
  Widget _buildConfirmedBannerState(TransactionModel tx) {
    final amountDisplay = tx.amount != null ? currencyFormatter.format(tx.amount) : '₱0.00';
    final providerName = tx.provider.isNotEmpty ? tx.provider : tx.source;

    Color providerColor;
    if (providerName.toLowerCase().contains('maya')) {
      providerColor = const Color(0xFF00D68F);
    } else if (providerName.toLowerCase().contains('maribank')) {
      providerColor = const Color(0xFFFF5722);
    } else {
      providerColor = const Color(0xFF005CE6);
    }

    return Center(
      key: const ValueKey('confirmed_state'),
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
                color: const Color(0xFF00E676).withValues(alpha: 0.25),
                blurRadius: 50,
                spreadRadius: 10,
              ),
            ],
            border: Border.all(color: const Color(0xFF00E676), width: 3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Large GREEN Verified Icon Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, size: 96, color: Color(0xFF00E676)),
              ),
              const SizedBox(height: 24),
              // Large GREEN PAYMENT CONFIRMED Banner Title
              const Text(
                'PAYMENT CONFIRMED!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Color(0xFF00E676),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Thank you! Your transaction has been verified instantly.',
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 32),
              // Amount Display
              Text(
                amountDisplay,
                style: const TextStyle(
                  fontSize: 68,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              // Payment Details Box (Provider, Sender Name, Ref No)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Payer: ${tx.senderName}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: providerColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: providerColor, width: 1),
                          ),
                          child: Text(
                            providerName,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: providerColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Safe Reference Number Retrieval & High-Visibility Display Badge
                    Builder(
                      builder: (context) {
                        final String refNumber = (tx.refNumber.trim().isNotEmpty && tx.refNumber.trim().toUpperCase() != 'NO_REF')
                            ? tx.refNumber.trim()
                            : 'N/A';

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.5), width: 1.5),
                          ),
                          child: SelectableText(
                            'Ref No: $refNumber',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF00E676), // High contrast bright emerald green
                              letterSpacing: 1.5,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 3. DUPLICATE PAYMENT WARNING STATE: Orange/Red Alert Banner
  Widget _buildDuplicateWarningState(TransactionModel tx) {
    final String refNumber = (tx.refNumber.trim().isNotEmpty && tx.refNumber.trim().toUpperCase() != 'NO_REF')
        ? tx.refNumber.trim()
        : 'N/A';

    return Center(
      key: const ValueKey('duplicate_warning_state'),
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
                color: Colors.orange.withValues(alpha: 0.3),
                blurRadius: 50,
                spreadRadius: 10,
              ),
            ],
            border: Border.all(color: Colors.orangeAccent, width: 3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, size: 96, color: Colors.orangeAccent),
              ),
              const SizedBox(height: 24),
              const Text(
                '⚠️ DUPLICATE PAYMENT DETECTED',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: Colors.orangeAccent,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Reference No: $refNumber has already been processed!',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.white70, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.5), width: 1.5),
                ),
                child: const Text(
                  'Transaction Rejected • Duplicate Prevented',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProviderBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }
}
