import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/data_models/product_list.dart';
import 'package:smooth_app/database/dao_product.dart';
import 'package:smooth_app/database/dao_product_list.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_norm.dart';

/// One company and the scanned products it owns.
class OwnerTally {
  OwnerTally({required this.owner, this.company});

  /// Display name: the researched company name when known.
  final String owner;
  final EthicsCompany? company;
  final List<Product> products = <Product>[];

  int get count => products.length;

  int? get ethicsScore => company == null ? null : EthicsScore.compute(company!).score;
}

/// "Who you buy from": the user's scanned products grouped by top owner,
/// from the offline database only (instant, no network).
class OwnerInsights {
  OwnerInsights._(this.owners, this.unknown);

  /// Most products first.
  final List<OwnerTally> owners;

  /// Products whose owner the offline data does not know.
  final List<Product> unknown;

  int get total => unknown.length + owners.fold(0, (int sum, OwnerTally t) => sum + t.count);

  /// The ethics score of what the user buys: the owners' scores weighted by
  /// how many products came from each. Null when no owner is rated.
  int? get averageEthics {
    int sum = 0;
    int n = 0;
    for (final OwnerTally t in owners) {
      final int? score = t.ethicsScore;
      if (score != null) {
        sum += score * t.count;
        n += t.count;
      }
    }
    return n == 0 ? null : (sum / n).round();
  }

  /// The scan history, newest first, as stored on the phone.
  static Future<List<Product>> historyProducts(final LocalDatabase localDatabase) async {
    final ProductList history = ProductList.history();
    await DaoProductList(localDatabase).get(history);
    final List<String> barcodes = history.getList();
    final Map<String, Product> products = await DaoProduct(localDatabase).getAll(barcodes);
    return <Product>[
      for (final String b in barcodes)
        if (products[b] != null) products[b]!,
    ];
  }

  /// The tally for [names] (owner name, display name ...), if any product matched.
  OwnerTally? tallyFor(final Iterable<String> names) {
    final Set<String> keys = names.map(OwnershipNorm.normCore).toSet();
    for (final OwnerTally t in owners) {
      if (keys.contains(OwnershipNorm.normCore(t.owner)) ||
          (t.company != null && keys.contains(OwnershipNorm.normCore(t.company!.name)))) {
        return t;
      }
    }
    return null;
  }

  static OwnerInsights compute(
    final Iterable<Product> products,
    final OwnershipLocalDb db, {
    final EthicsDb? ethics,
  }) {
    final Map<String, OwnerTally> byOwner = <String, OwnerTally>{};
    final List<Product> unknown = <Product>[];
    for (final Product p in products) {
      final LocalOwnerResult? hit = db.lookup(
        barcode: p.barcode ?? '',
        brands: p.brands,
        countryTags: p.countriesTags ?? const <String>[],
        embCodeTags: OwnershipLocalDb.embCodeTags(p.embCodes),
      );
      if (hit == null) {
        unknown.add(p);
        continue;
      }
      final EthicsCompany? company = ethics?.forOwner(hit.owner, chain: hit.ethicsChain);
      final String name = EthicsDb.displayName(hit.owner, company);
      // "Nestle" and "Nestlé" are one company.
      byOwner.putIfAbsent(OwnershipNorm.normCore(name), () => OwnerTally(owner: name, company: company)).products.add(p);
    }
    final List<OwnerTally> owners = byOwner.values.toList()
      ..sort((OwnerTally a, OwnerTally b) {
        final int c = b.count.compareTo(a.count);
        return c != 0 ? c : a.owner.toLowerCase().compareTo(b.owner.toLowerCase());
      });
    return OwnerInsights._(owners, unknown);
  }
}
