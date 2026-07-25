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
  final double? amount;
  final String refNumber;
  final String senderName;
  final String source; // e.g., 'GCash', 'Maya'
  final DateTime timestamp;
  final String status; // 'VERIFIED', 'DUPLICATE_REJECTED', 'SCAM_FLAGGED'
  final String sender; // e.g., 'GCash'
  final String message; // Full SMS body text
  final bool isScam; // True for phishing/scam attempts
  final String threatLevel; // 'LOW' or 'HIGH'

  const TransactionModel({
    required this.id,
    required this.merchantId,
    this.amount,
    required this.refNumber,
    required this.senderName,
    required this.source,
    required this.timestamp,
    required this.status,
    required this.sender,
    required this.message,
    required this.isScam,
    required this.threatLevel,
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

    final bool isScamVal = (map['isScam'] == true) || (map['is_scam'] == true);
    final String threatLevelVal = (map['threatLevel'] as String?) ??
        (map['threat_level'] as String?) ??
        (isScamVal ? 'HIGH' : 'LOW');
    final String senderVal = (map['sender'] as String?) ?? (map['source'] as String?) ?? 'GCash';
    final String messageVal = (map['message'] as String?) ?? '';

    return TransactionModel(
      id: id ?? (map['id'] as String?) ?? '',
      merchantId: (map['merchant_id'] as String?) ?? '',
      amount: (map['amount'] as num?)?.toDouble(),
      refNumber: (map['ref_number'] as String?) ?? '',
      senderName: (map['sender_name'] as String?) ?? (isScamVal ? 'SUSPICIOUS SENDER' : 'UNKNOWN SENDER'),
      source: (map['source'] as String?) ?? senderVal,
      timestamp: parsedTimestamp,
      status: (map['status'] as String?) ?? (isScamVal ? 'SCAM_FLAGGED' : TransactionStatus.verified.value),
      sender: senderVal,
      message: messageVal,
      isScam: isScamVal,
      threatLevel: threatLevelVal,
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
  /// Uses FieldValue.serverTimestamp() when [useServerTimestamp] is true.
  Map<String, dynamic> toMap({bool useServerTimestamp = false}) {
    return {
      'id': id,
      'merchant_id': merchantId,
      'amount': amount,
      'ref_number': refNumber,
      'sender_name': senderName,
      'source': source,
      'sender': sender,
      'message': message,
      'isScam': isScam,
      'threatLevel': threatLevel,
      'timestamp': useServerTimestamp ? FieldValue.serverTimestamp() : Timestamp.fromDate(timestamp),
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
    String? sender,
    String? message,
    bool? isScam,
    String? threatLevel,
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
      sender: sender ?? this.sender,
      message: message ?? this.message,
      isScam: isScam ?? this.isScam,
      threatLevel: threatLevel ?? this.threatLevel,
    );
  }

  /// Helper boolean to quickly verify if the transaction status is verified.
  bool get isVerified => !isScam && status.toUpperCase() == TransactionStatus.verified.value;

  /// Helper boolean to check if transaction was flagged as duplicate.
  bool get isDuplicate => status.toUpperCase() == TransactionStatus.duplicateRejected.value;

  @override
  String toString() {
    return 'TransactionModel(id: $id, merchantId: $merchantId, amount: $amount, refNumber: $refNumber, senderName: $senderName, source: $source, sender: $sender, isScam: $isScam, threatLevel: $threatLevel, timestamp: $timestamp, status: $status)';
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
        other.sender == sender &&
        other.message == message &&
        other.isScam == isScam &&
        other.threatLevel == threatLevel &&
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
      sender,
      message,
      isScam,
      threatLevel,
      timestamp,
      status,
    );
  }
}
