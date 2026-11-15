import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_norm.dart';

/// A company the app knows something about: researched (ethics) and/or a
/// big group with a ranked brand list.
class OwnerRef {
  const OwnerRef({required this.name, this.company, this.dbName});

  /// Display name.
  final String name;
  final EthicsCompany? company;

  /// The name as stored in the ownership database, for its brand list.
  final String? dbName;
}

/// Finds companies by name for the search screen ("nestl" -> Nestlé).
class OwnerDirectory {
  OwnerDirectory(final OwnershipLocalDb? ownerDb, final EthicsDb? ethicsDb) {
    final Map<String, OwnerRef> byKey = <String, OwnerRef>{};
    for (final EthicsCompany c in ethicsDb?.companies ?? const <EthicsCompany>[]) {
      byKey[OwnershipNorm.normCore(c.name)] = OwnerRef(name: c.name, company: c);
    }
    for (final String owner in ownerDb?.topOwners ?? const <String>[]) {
      final EthicsCompany? c = ethicsDb?.forOwner(owner);
      final String key = OwnershipNorm.normCore(c?.name ?? owner);
      final OwnerRef? known = byKey[key];
      byKey[key] = OwnerRef(name: known?.name ?? c?.name ?? owner, company: known?.company ?? c, dbName: owner);
    }
    for (final MapEntry<String, OwnerRef> e in byKey.entries) {
      _entries.add((e.key, e.value));
      for (final String alias in e.value.company?.matchNames ?? const <String>[]) {
        _aliases.add((OwnershipNorm.normCore(alias), e.value));
      }
    }
  }

  final List<(String, OwnerRef)> _entries = <(String, OwnerRef)>[];
  final List<(String, OwnerRef)> _aliases = <(String, OwnerRef)>[];

  /// Companies whose name (or a word in it) starts with [query]; best first.
  List<OwnerRef> search(final String query, {final int limit = 3}) {
    final String q = OwnershipNorm.normCore(query);
    if (q.length < 3) {
      return const <OwnerRef>[];
    }
    final List<(int, OwnerRef)> scored = <(int, OwnerRef)>[];
    final Set<String> seen = <String>{};
    void consider(final String key, final OwnerRef ref) {
      if (seen.contains(ref.name)) {
        return;
      }
      int score;
      if (key == q) {
        score = 0;
      } else if (key.startsWith(q)) {
        score = 1;
      } else if (key.split(' ').any((String w) => w.startsWith(q))) {
        score = 2;
      } else {
        return;
      }
      seen.add(ref.name);
      scored.add((score, ref));
    }

    for (final (String key, OwnerRef ref) in _entries) {
      consider(key, ref);
    }
    for (final (String key, OwnerRef ref) in _aliases) {
      // Aliases only on a full-word match: "lu" should not find everything.
      if (key == q || key.startsWith('$q ')) {
        consider(key, ref);
      }
    }
    scored.sort(((int, OwnerRef) a, (int, OwnerRef) b) {
      final int c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.name.length.compareTo(b.$2.name.length);
    });
    return scored.take(limit).map(((int, OwnerRef) e) => e.$2).toList();
  }
}
