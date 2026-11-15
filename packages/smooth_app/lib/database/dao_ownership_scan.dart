import 'dart:async';

import 'package:smooth_app/database/abstract_sql_dao.dart';
import 'package:sqflite/sqflite.dart';

/// Source of an ownership lookup, in order of trust.
enum OwnershipScanSource { barcodeMatch, aiGuess, manual }

/// Resolution state of an ownership scan.
enum OwnershipScanStatus { resolved, pendingConfirmation, unresolved }

/// Local log of ownership scans (one row per scan attempt on this device).
///
/// This never leaves the device. Confirmed brand/owner results are pushed
/// separately to the central `brand_owner` cache (see `ownership_service.dart`)
/// so other users benefit without re-running the AI fallback.
class DaoOwnershipScan extends AbstractSqlDao {
  DaoOwnershipScan(super.localDatabase);

  static const String _table = 'ownership_scan';
  static const String _columnId = 'id';
  static const String _columnBarcode = 'barcode';
  static const String _columnCountryCode = 'country_code';
  static const String _columnTimestamp = 'timestamp';
  static const String _columnSource = 'source';
  static const String _columnConfidence = 'confidence';
  static const String _columnStatus = 'status';
  static const String _columnGuessedName = 'guessed_name';

  static FutureOr<void> onUpgrade(
    final Database db,
    final int oldVersion,
    final int newVersion,
  ) async {
    if (oldVersion < 10) {
      await db.execute(
        'create table $_table('
        ' $_columnId INTEGER PRIMARY KEY AUTOINCREMENT'
        ',$_columnBarcode TEXT'
        ',$_columnCountryCode TEXT NOT NULL'
        ',$_columnTimestamp INT NOT NULL'
        ',$_columnSource TEXT NOT NULL'
        ',$_columnConfidence REAL'
        ',$_columnStatus TEXT NOT NULL'
        ',$_columnGuessedName TEXT'
        ')',
      );
    }
  }

  Future<int> insertScan({
    required final String? barcode,
    required final String countryCode,
    required final OwnershipScanSource source,
    required final OwnershipScanStatus status,
    final double? confidence,
    final String? guessedName,
  }) => localDatabase.database.insert(_table, <String, Object?>{
    _columnBarcode: barcode,
    _columnCountryCode: countryCode,
    _columnTimestamp: DateTime.now().millisecondsSinceEpoch,
    _columnSource: source.name,
    _columnConfidence: confidence,
    _columnStatus: status.name,
    _columnGuessedName: guessedName,
  });

  Future<int> updateStatus(final int id, final OwnershipScanStatus status) =>
      localDatabase.database.update(
        _table,
        <String, Object?>{_columnStatus: status.name},
        where: '$_columnId = ?',
        whereArgs: <int>[id],
      );

  /// Scans still waiting for the user to confirm an AI guess.
  Future<List<Map<String, Object?>>> getPendingConfirmations() =>
      localDatabase.database.query(
        _table,
        where: '$_columnStatus = ?',
        whereArgs: <String>[OwnershipScanStatus.pendingConfirmation.name],
        orderBy: '$_columnTimestamp DESC',
      );
}
