import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  final currencyFormatter = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _scheduleReset(int remainingSeconds) {
    _resetTimer?.cancel();
    if (remainingSeconds > 0) {
      _resetTimer = Timer(Duration(seconds: remainingSeconds), () {
        if (mounted) {
          setState(() {}); // Trigger rebuild to revert to Idle State after 15s
        }
      });
    }
  }

  Stream<TransactionModel?> _getLatestTransactionStream() {
    try {
      return FirebaseFirestore.instance
          .collection('transactions')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots()
          .map((snapshot) {
        if (snapshot.docs.isEmpty) return null;
        return TransactionModel.fromFirestore(snapshot.docs.first);
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

          bool isRecent = false;
          if (latestTx != null && latestTx.isVerified && !latestTx.isScam) {
            final diffInSeconds = DateTime.now().difference(latestTx.timestamp).inSeconds;
            if (diffInSeconds >= 0 && diffInSeconds <= 15) {
              isRecent = true;
              _scheduleReset(15 - diffInSeconds);
            }
          }

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: isRecent && latestTx != null
                ? _buildConfirmedBannerState(latestTx)
                : _buildIdleWaitingState(),
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
                    const SizedBox(height: 8),
                    Text(
                      'Ref No: ${tx.refNumber}',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
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
