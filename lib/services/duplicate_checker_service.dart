import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Default Hive box key for storing verified payment reference numbers.
const String kVerifiedRefNumbersBox = 'verified_ref_numbers';

/// Service responsible for fast offline duplicate reference number detection using Hive.
class DuplicateCheckerService {
  final Box<String> _box;

  /// Private constructor taking an opened Hive box.
  DuplicateCheckerService(this._box);

  /// Factory constructor to obtain an instance with the default initialized Hive box.
  factory DuplicateCheckerService.instance() {
    if (!Hive.isBoxOpen(kVerifiedRefNumbersBox)) {
      throw StateError(
        'Hive box "$kVerifiedRefNumbersBox" is not open. Ensure Hive.openBox() is called during main initialization.',
      );
    }
    final box = Hive.box<String>(kVerifiedRefNumbersBox);
    return DuplicateCheckerService(box);
  }

  /// Checks whether a payment reference number has already been verified and stored locally.
  /// Returns `true` if the reference number is a duplicate, otherwise `false`.
  bool isReferenceDuplicate(String refNumber) {
    if (refNumber.trim().isEmpty) return false;
    final sanitizedRef = refNumber.trim().toUpperCase();
    final exists = _box.containsKey(sanitizedRef);
    debugPrint('[DuplicateCheckerService] Checking ref "$sanitizedRef": ${exists ? "DUPLICATE FOUND" : "UNIQUE"}');
    return exists;
  }

  /// Saves a newly verified reference number into the local Hive storage.
  /// Stores ISO8601 timestamp string as value for audit tracking.
  Future<void> saveReferenceLocally(String refNumber) async {
    if (refNumber.trim().isEmpty) return;
    final sanitizedRef = refNumber.trim().toUpperCase();
    final timestamp = DateTime.now().toIso8601String();
    await _box.put(sanitizedRef, timestamp);
    debugPrint('[DuplicateCheckerService] Saved ref "$sanitizedRef" locally in Hive at $timestamp.');
  }

  /// Returns the total number of cached reference numbers stored locally.
  int getCachedReferenceCount() {
    return _box.length;
  }

  /// Clears all stored reference numbers (useful for testing or merchant reset).
  Future<void> clearAllReferences() async {
    await _box.clear();
    debugPrint('[DuplicateCheckerService] Cleared all local reference numbers from Hive.');
  }
}
