import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/services/ownership_norm.dart';

/// Companies the user wants to avoid. Kept on the phone only; every screen
/// that shows an owner can warn when it is on this list.
class AvoidedOwners extends ChangeNotifier {
  AvoidedOwners._();

  static final AvoidedOwners instance = AvoidedOwners._();

  static const String _prefsKey = 'owned_avoided_owners';
  static const String _hideKey = 'owned_hide_avoided_in_search';

  /// Leave products from avoided companies out of search results.
  bool get hideInSearch => _hideInSearch;
  bool _hideInSearch = false;

  Future<void> setHideInSearch(final bool value) async {
    _hideInSearch = value;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hideKey, value);
    } catch (_) {
      // Kept for this session.
    }
  }

  /// Display name by normalised name, in the order they were added.
  final Map<String, String> _owners = <String, String>{};
  Future<void>? _loading;

  /// Loads the saved list once; safe to call from any build.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      for (final String name in prefs.getStringList(_prefsKey) ?? const <String>[]) {
        _owners[OwnershipNorm.normCore(name)] = name;
      }
      _hideInSearch = prefs.getBool(_hideKey) ?? false;
    } catch (_) {
      // No storage (tests, first run): start with an empty list.
    }
    notifyListeners();
  }

  /// Display names, oldest first.
  List<String> get names => List<String>.unmodifiable(_owners.values);

  bool get isEmpty => _owners.isEmpty;

  /// True when any of [names] (owner, display name, chain, controller) is avoided.
  bool isAvoided(final Iterable<String?> names) => avoidedName(names) != null;

  /// The avoided display name matching one of [names], if any.
  String? avoidedName(final Iterable<String?> names) {
    if (_owners.isEmpty) {
      return null;
    }
    for (final String? n in names) {
      if (n == null || n.trim().isEmpty) {
        continue;
      }
      final String? hit = _owners[OwnershipNorm.normCore(n)];
      if (hit != null) {
        return hit;
      }
    }
    return null;
  }

  Future<void> add(final String name) async {
    await load();
    _owners[OwnershipNorm.normCore(name)] = name;
    notifyListeners();
    await _save();
  }

  Future<void> remove(final String name) async {
    await load();
    _owners.remove(OwnershipNorm.normCore(name));
    notifyListeners();
    await _save();
  }

  Future<void> toggle(final String name) =>
      _owners.containsKey(OwnershipNorm.normCore(name)) ? remove(name) : add(name);

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _owners.values.toList());
    } catch (_) {
      // Kept in memory for this session.
    }
  }

  @visibleForTesting
  void resetForTest() {
    _owners.clear();
    _hideInSearch = false;
    _loading = null;
  }
}
