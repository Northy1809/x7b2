import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/services/ownership_norm.dart';

/// One correction: what it applies to (brand as typed on the pack, or a
/// barcode) and the owner the user named.
class OwnerCorrection {
  const OwnerCorrection({required this.key, required this.label, required this.owner});

  final String key;

  /// The brand as shown on the pack, or the barcode.
  final String label;
  final String owner;

  bool get isBarcode => key.startsWith('c:');
}

/// Owners the user corrected by hand ("Not right?"). Kept on the phone only
/// and checked before the offline database, so every screen shows the
/// correction. Keyed by brand, or by barcode when the product has no brand.
class OwnerOverrides extends ChangeNotifier {
  OwnerOverrides._();

  static final OwnerOverrides instance = OwnerOverrides._();

  static const String _prefsKey = 'owned_owner_overrides';

  /// By key: `b:` + normalised brand, or `c:` + barcode. Newest last.
  final Map<String, OwnerCorrection> _byKey = <String, OwnerCorrection>{};
  Future<void>? _loading;

  /// Loads the saved corrections once; safe to call from any build.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw != null) {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((String k, dynamic v) {
          final Map<String, dynamic> m = v as Map<String, dynamic>;
          _byKey[k] = OwnerCorrection(key: k, label: m['l'] as String, owner: m['o'] as String);
        });
      }
    } catch (_) {
      // No storage (tests, first run) or a broken value: start empty.
    }
    notifyListeners();
  }

  bool get isEmpty => _byKey.isEmpty;

  /// All corrections, newest first.
  List<OwnerCorrection> get all => _byKey.values.toList().reversed.toList();

  /// The first brand on the pack that counts, as typed.
  static String? _firstBrand(final String? brands) {
    for (final String raw in OwnershipNorm.splitBrands(brands)) {
      final String key = OwnershipNorm.normCore(raw);
      if (key.isNotEmpty && !OwnershipNorm.stopBrands.contains(key)) {
        return raw;
      }
    }
    return null;
  }

  /// The user's owner for this product: any brand on the pack, then the barcode.
  String? ownerFor({required final String barcode, final String? brands}) {
    if (_byKey.isEmpty) {
      return null;
    }
    for (final String raw in OwnershipNorm.splitBrands(brands)) {
      final OwnerCorrection? hit = _byKey['b:${OwnershipNorm.normCore(raw)}'];
      if (hit != null) {
        return hit.owner;
      }
    }
    return _byKey['c:$barcode']?.owner;
  }

  Future<void> set({
    required final String barcode,
    required final String? brands,
    required final String owner,
  }) async {
    await load();
    final String name = owner.trim();
    if (name.isEmpty) {
      return remove(barcode: barcode, brands: brands);
    }
    final String? brand = _firstBrand(brands);
    final String key = brand == null ? 'c:$barcode' : 'b:${OwnershipNorm.normCore(brand)}';
    _byKey.remove(key);
    _byKey[key] = OwnerCorrection(key: key, label: brand ?? barcode, owner: name);
    notifyListeners();
    await _save();
  }

  /// Removes every correction that applies to this product.
  Future<void> remove({required final String barcode, final String? brands}) async {
    await load();
    _byKey.remove('c:$barcode');
    for (final String raw in OwnershipNorm.splitBrands(brands)) {
      _byKey.remove('b:${OwnershipNorm.normCore(raw)}');
    }
    notifyListeners();
    await _save();
  }

  Future<void> removeCorrection(final OwnerCorrection c) async {
    await load();
    _byKey.remove(c.key);
    notifyListeners();
    await _save();
  }

  /// Puts back a correction that was just removed (undo).
  Future<void> restore(final OwnerCorrection c) async {
    await load();
    _byKey[c.key] = c;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(<String, Object>{
          for (final OwnerCorrection c in _byKey.values) c.key: <String, String>{'l': c.label, 'o': c.owner},
        }),
      );
    } catch (_) {
      // Kept in memory for this session.
    }
  }

  @visibleForTesting
  void resetForTest() {
    _byKey.clear();
    _loading = null;
  }
}
