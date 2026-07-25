import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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

  /// Stream builder for Store User Profile (Retrieves QR code Base64/URLs).
  Stream<DocumentSnapshot<Map<String, dynamic>>?> _getStoreUserStream() {
    try {
      if (Firebase.apps.isEmpty) return Stream.value(null);
      final String? uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return Stream.value(null);
      return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    } catch (_) {
      return Stream.value(null);
    }
  }

  /// 1. DEFAULT IDLE STATE: "Scan to Pay via GCash / Maya / MariBank" with Dynamic Store QR Codes
  Widget _buildIdleWaitingState() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      stream: _getStoreUserStream(),
      builder: (context, userSnapshot) {
        String? gcashQrData;
        String? mayaQrData;
        String? maribankQrData;

        if (userSnapshot.hasData && userSnapshot.data != null && userSnapshot.data!.exists) {
          final data = userSnapshot.data!.data();
          if (data != null) {
            gcashQrData = data['gcash_qr_base64']?.toString().trim() ?? data['gcash_qr_url']?.toString().trim();
            mayaQrData = data['maya_qr_base64']?.toString().trim() ?? data['maya_qr_url']?.toString().trim();
            maribankQrData = data['maribank_qr_base64']?.toString().trim() ?? data['maribank_qr_url']?.toString().trim();

            if (gcashQrData != null && gcashQrData.isEmpty) gcashQrData = null;
            if (mayaQrData != null && mayaQrData.isEmpty) mayaQrData = null;
            if (maribankQrData != null && maribankQrData.isEmpty) maribankQrData = null;
          }
        }

        final bool hasQrCodes = (gcashQrData != null) || (mayaQrData != null) || (maribankQrData != null);

        return Center(
          key: const ValueKey('idle_state'),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 900),
              padding: const EdgeInsets.all(36),
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
                  // Header Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.qr_code_2, size: 36, color: Color(0xFF00E676)),
                      ),
                      const SizedBox(width: 14),
                      const Text(
                        'Scan to Pay via E-Wallet',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Instant payment verification protected by PaymentGuard PH',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 28),

                  // Dynamic QR Code Display Cards
                  if (hasQrCodes)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 700;
                        final qrCards = [
                          if (gcashQrData != null)
                            _buildQrCodeCard('GCash QR Code', gcashQrData, const Color(0xFF005CE6)),
                          if (mayaQrData != null)
                            _buildQrCodeCard('Maya QR Code', mayaQrData, const Color(0xFF00D68F)),
                          if (maribankQrData != null)
                            _buildQrCodeCard('MariBank QR Code', maribankQrData, const Color(0xFFFF5722)),
                        ];

                        if (isNarrow) {
                          return Column(children: qrCards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 16), child: c)).toList());
                        }

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: qrCards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: c))).toList(),
                        );
                      },
                    )
                  else ...[
                    // Pulse/Listening Animation Fallback when QR URLs are not set
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF00E676).withValues(alpha: 0.08),
                          ),
                        ),
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF00E676).withValues(alpha: 0.15),
                          ),
                        ),
                        const Icon(Icons.qr_code_scanner, size: 52, color: Color(0xFF00E676)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Waiting for Payment...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),
                  const Divider(color: Color(0xFF334155)),
                  const SizedBox(height: 20),
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
      },
    );
  }

  Widget _buildQrCodeCard(String title, String qrData, Color brandColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brandColor.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: brandColor.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: brandColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: brandColor.withValues(alpha: 0.5)),
            ),
            child: Text(
              title,
              style: TextStyle(color: brandColor, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: _buildQrImageWidget(qrData),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrImageWidget(String qrData) {
    if (qrData.startsWith('http://') || qrData.startsWith('https://')) {
      return Image.network(
        qrData,
        height: 220,
        width: 220,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: 220,
            width: 220,
            color: Colors.grey.shade900,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, size: 48, color: Colors.white38),
                SizedBox(height: 8),
                Text('Failed to load QR image', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          );
        },
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
        height: 220,
        width: 220,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: 220,
            width: 220,
            color: Colors.grey.shade900,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, size: 48, color: Colors.white38),
                SizedBox(height: 8),
                Text('Failed to load QR image', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          );
        },
      );
    } catch (_) {
      return Container(
        height: 220,
        width: 220,
        color: Colors.grey.shade900,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, size: 48, color: Colors.white38),
            SizedBox(height: 8),
            Text('Invalid QR Image Data', style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      );
    }
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
