import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:smooth_app/helpers/gs1_code.dart';
import 'package:smooth_app/services/brand_text_matcher.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_norm.dart';
import 'package:smooth_app/services/photo_analyzer.dart';

/// One photo of the test set and what reading it gave.
class SelfTestItem {
  SelfTestItem({required this.file, required this.code, required this.kind, this.brands = ''});

  factory SelfTestItem.fromJson(final Map<String, dynamic> j) => SelfTestItem(
    file: j['file'] as String,
    code: j['code'] as String,
    kind: j['kind'] as String,
    brands: j['brands'] as String? ?? '',
  );

  final String file;

  /// The product's barcode.
  final String code;

  /// "bc": a real photo with the barcode on it; "hard": the same made
  /// harder (small, dark, blurred, turned, glare); "front": the front of
  /// the pack, read for its brand.
  final String kind;

  /// The product's brands, comma separated (Open Food Facts).
  final String brands;

  String? got;
  String how = '';
  int ms = 0;
  bool? ok;
  String owner = '';

  bool get isBarcode => kind != 'front';
}

/// 23/11 2026: proof that the scanner reads products, on the phone itself:
/// real photos of packs (Open Food Facts) and harder versions of them are
/// read by the same code as a camera photo, with the phone's own barcode
/// and text readers. Every result is printed as "OWNED_SELFTEST ..." for
/// the device log. Opened by holding the wordmark on the camera.
class ScanSelfTestPage extends StatefulWidget {
  const ScanSelfTestPage({super.key});

  static const String base = 'https://raw.githubusercontent.com/Northy1809/x7b2/t/';

  @override
  State<ScanSelfTestPage> createState() => _ScanSelfTestPageState();
}

class _ScanSelfTestPageState extends State<ScanSelfTestPage> {
  final List<SelfTestItem> _items = <SelfTestItem>[];
  String _status = 'Loading the test photos';
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  static String _norm(final String code) => Gs1Code.toProductCode(code) ?? code;

  void _log(final String line) => debugPrint('OWNED_SELFTEST $line');

  Future<void> _run() async {
    try {
      final http.Response r = await http
          .get(Uri.parse('${ScanSelfTestPage.base}manifest.json'))
          .timeout(const Duration(seconds: 30));
      final Map<String, dynamic> m = jsonDecode(r.body) as Map<String, dynamic>;
      _items.addAll(<SelfTestItem>[
        for (final dynamic j in m['items'] as List<dynamic>) SelfTestItem.fromJson(j as Map<String, dynamic>),
      ]);
    } catch (e) {
      setState(() => _status = 'Could not load the test set: $e');
      _log('ERROR manifest $e');
      return;
    }
    final Directory dir = await getTemporaryDirectory();
    final OwnershipLocalDb db = await OwnershipLocalDb.load();
    _log('START ${_items.length} photos');
    for (int i = 0; i < _items.length; i++) {
      if (!mounted) {
        return;
      }
      final SelfTestItem item = _items[i];
      setState(() => _status = 'Reading ${i + 1} of ${_items.length}');
      final File file = File('${dir.path}/selftest_${item.file}');
      try {
        if (!file.existsSync()) {
          final http.Response r = await http
              .get(Uri.parse('${ScanSelfTestPage.base}${item.file}'))
              .timeout(const Duration(seconds: 60));
          await file.writeAsBytes(r.bodyBytes, flush: true);
        }
        final Stopwatch w = Stopwatch()..start();
        final PhotoAnalyzer analyzer = PhotoAnalyzer(online: (_) async => null);
        final PhotoAnalysis a = await analyzer.analyze(file.path, countryTags: const <String>['en:denmark']);
        item.ms = w.elapsedMilliseconds;
        item.got = a.barcode;
        item.how = analyzer.lastRun;
        if (item.isBarcode) {
          item.ok = a.barcode != null && _norm(a.barcode!) == _norm(item.code);
          final LocalOwnerResult? o = db.lookup(barcode: item.code, brands: item.brands, countryTags: const <String>['en:denmark']);
          item.owner = o?.owner ?? '';
        } else {
          final Set<String> want = <String>{
            for (final String b in item.brands.split(',')) OwnershipNorm.normCore(b),
          }..removeWhere((String b) => b.isEmpty);
          final bool brandOk = a.brands.any(
            (BrandCandidate c) => want.contains(OwnershipNorm.normCore(c.name)) || want.contains(c.key),
          );
          final bool codeOk = a.barcode != null && _norm(a.barcode!) == _norm(item.code);
          item.ok = brandOk || codeOk;
          item.got = a.barcode ?? (a.brands.isEmpty ? null : a.brands.first.name);
          item.owner = a.brands.isEmpty ? '' : a.brands.first.owner.owner;
        }
      } catch (e) {
        item.ok = false;
        item.how = 'error $e';
      }
      _log('${item.ok == true ? 'OK  ' : 'MISS'} ${i + 1}/${_items.length} ${item.kind} ${item.file} '
          'want=${item.code} got=${item.got ?? '-'} owner="${item.owner}" ms=${item.ms} ${item.how}');
      try {
        file.deleteSync();
      } catch (_) {}
    }
    final String summary = _summary();
    _log('DONE $summary');
    if (mounted) {
      setState(() {
        _done = true;
        _status = summary;
      });
    }
  }

  String _summary() {
    String part(final String kind, final String label) {
      final List<SelfTestItem> of = _items.where((SelfTestItem i) => i.kind == kind && i.ok != null).toList();
      if (of.isEmpty) {
        return '';
      }
      final int ok = of.where((SelfTestItem i) => i.ok!).length;
      return '$label $ok/${of.length}';
    }

    return <String>[
      part('bc', 'Barcode photos'),
      part('hard', 'Hard photos'),
      part('front', 'Fronts'),
    ].where((String s) => s.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<SelfTestItem> read = _items.where((SelfTestItem i) => i.ok != null).toList().reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner self-test')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: <Widget>[
                if (!_done) const SizedBox.square(dimension: 18.0, child: CircularProgressIndicator(strokeWidth: 2.0)),
                if (!_done) const SizedBox(width: 12.0),
                Expanded(child: Text(_status, style: theme.textTheme.titleMedium)),
              ],
            ),
          ),
          if (read.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(alignment: Alignment.centerLeft, child: Text(_summary())),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: read.length,
              itemBuilder: (BuildContext context, int i) {
                final SelfTestItem item = read[i];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    item.ok! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: item.ok! ? Colors.green : Colors.red,
                  ),
                  title: Text('${item.kind} ${item.code}'),
                  subtitle: Text('Got ${item.got ?? 'nothing'} · ${item.owner} · ${item.ms} ms'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
