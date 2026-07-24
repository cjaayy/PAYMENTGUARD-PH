import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of the payment transaction verification.
enum TransactionStatus {
  verified('VERIFIED'),
  duplicateRejected('DUPLICATE_REJECTED');

  final String value;
  const TransactionStatus(this.value);

  static TransactionStatus fromString(String status) {
    return TransactionStatus.values.firstWhere(
      (e) => e.value.toUpperCase() == status.toUpperCase(),
      orElse: () => TransactionStatus.verified,
    );
  }
}

/// Payment source (e-wallet service).
enum PaymentSource {
  gcash('GCash'),
  maya('Maya'),
  unknown('Unknown');

  final String value;
  const PaymentSource(this.value);

  static PaymentSource fromString(String source) {
    if (source.toUpperCase().contains('GCASH')) return PaymentSource.gcash;
    if (source.toUpperCase().contains('MAYA') || source.toUpperCase().contains('PAYMAYA')) {
      return PaymentSource.maya;
    }
    return PaymentSource.unknown;
  }
}

/// Data Model representing a payment transaction stored in Cloud Firestore (`transactions` collection).
class TransactionModel {
  final String id;
  final String merchantId;
  final double amount;
  final String refNumber;
  final String senderName;
  final String source; // e.g., 'GCash', 'Maya'
  final DateTime timestamp;
  final String status; // 'VERIFIED', 'DUPLICATE_REJECTED'

  const TransactionModel({
    required this.id,
    required this.merchantId,
    required this.amount,
    required this.refNumber,
    required this.senderName,
    required this.source,
    required this.timestamp,
    required this.status,
  });

  /// Factory constructor to create a [TransactionModel] from a Map (Firestore data).
  factory TransactionModel.fromMap(Map<String, dynamic> map, {String? id}) {
    DateTime parsedTimestamp;
    final dynamic tsRaw = map['timestamp'];

    if (tsRaw is Timestamp) {
      parsedTimestamp = tsRaw.toDate();
    } else if (tsRaw is String) {
      parsedTimestamp = DateTime.tryParse(tsRaw) ?? DateTime.now();
    } else if (tsRaw is int) {
      parsedTimestamp = DateTime.fromMillisecondsSinceEpoch(tsRaw);
    } else {
      parsedTimestamp = DateTime.now();
    }

    return TransactionModel(
      id: id ?? map['id'] ?? '',
      merchantId: map['merchant_id'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      refNumber: map['ref_number'] as String? ?? '',
      senderName: map['sender_name'] as String? ?? 'UNKNOWN SENDER',
      source: map['source'] as String? ?? 'GCash',
      timestamp: parsedTimestamp,
      status: map['status'] as String? ?? TransactionStatus.verified.value,
    );
  }

  /// Factory constructor to create a [TransactionModel] from a Firestore DocumentSnapshot.
  factory TransactionModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) {
      throw Exception("Transaction document snapshot data is null for ID: ${snapshot.id}");
    }
    return TransactionModel.fromMap(data, id: snapshot.id);
  }

  /// Converts the [TransactionModel] instance to a Map suitable for Cloud Firestore writes.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'merchant_id': merchantId,
      'amount': amount,
      'ref_number': refNumber,
      'sender_name': senderName,
      'source': source,
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status,
    };
  }

  /// Returns a copy of this [TransactionModel] with updated fields.
  TransactionModel copyWith({
    String? id,
    String? merchantId,
    double? amount,
    String? refNumber,
    String? senderName,
    String? source,
    DateTime? timestamp,
    String? status,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      merchantId: merchantId ?? this.merchantId,
      amount: amount ?? this.amount,
      refNumber: refNumber ?? this.refNumber,
      senderName: senderName ?? this.senderName,
      source: source ?? this.source,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
    );
  }

  /// Helper boolean to quickly verify if the transaction status is verified.
  bool get isVerified => status.toUpperCase() == TransactionStatus.verified.value;

  /// Helper boolean to check if transaction was flagged as duplicate.
  bool get isDuplicate => status.toUpperCase() == TransactionStatus.duplicateRejected.value;

  @override
  String toString() {
    return 'TransactionModel(id: $id, merchantId: $merchantId, amount: $amount, refNumber: $refNumber, senderName: $senderName, source: $source, timestamp: $timestamp, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TransactionModel &&
        other.id == id &&
        other.merchantId == merchantId &&
        other.amount == amount &&
        other.refNumber == refNumber &&
        other.senderName == senderName &&
        other.source == source &&
        other.timestamp == timestamp &&
        other.status == status;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      merchantId,
      amount,
      refNumber,
      senderName,
      source,
      timestamp,
      status,
    );
  }
}
