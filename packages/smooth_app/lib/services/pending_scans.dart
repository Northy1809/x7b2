import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/services/photo_analyzer.dart';

/// One photo being read, shown as a row at the top of the home page while
/// it runs (as Cal AI does with a meal photo), then as its answer.
class PendingScan {
  PendingScan(this.imagePath) : startedAt = DateTime.now();

  final String imagePath;
  final DateTime startedAt;

  /// What the reader is doing ("Reading the pack").
  String step = PhotoAnalyzer.steps.first;

  /// 0-1 for the ring; reaches 1 when [analysis] is in.
  double progress = 0.0;

  PhotoAnalysis? analysis;

  /// The reader failed; the row offers to open the photo anyway.
  bool failed = false;

  bool get done => analysis != null || failed;
}

/// The photos being read in the background, newest first. Kept for this
/// run of the app only: once read, a product lands in the history.
class PendingScans extends ChangeNotifier {
  PendingScans._();

  static final PendingScans instance = PendingScans._();

  final List<PendingScan> _scans = <PendingScan>[];

  List<PendingScan> get scans => List<PendingScan>.unmodifiable(_scans);

  /// For tests.
  PhotoAnalyzer Function() analyzerFactory = PhotoAnalyzer.new;

  /// Starts reading [imagePath]; the home page shows it straight away.
  PendingScan start(final String imagePath, {final List<String>? countryTags, final String? barcode}) {
    final PendingScan scan = PendingScan(imagePath);
    _scans.insert(0, scan);
    if (_scans.length > 5) {
      _scans.removeLast();
    }
    notifyListeners();
    unawaited(_run(scan, countryTags ?? <String>[ProductQuery.getCountry().offTag], barcode));
    return scan;
  }

  void remove(final PendingScan scan) {
    if (_scans.remove(scan)) {
      notifyListeners();
    }
  }

  Future<void> _run(final PendingScan scan, final List<String> countryTags, [final String? barcode]) async {
    // The ring creeps towards 90 % while the reader works, as Cal AI's
    // percentage does, and closes when the answer is in.
    final Timer ticker = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (scan.done) {
        return;
      }
      scan.progress += (0.9 - scan.progress) * 0.035;
      notifyListeners();
    });
    try {
      final PhotoAnalysis analysis = await analyzerFactory().analyze(
        scan.imagePath,
        countryTags: countryTags,
        liveBarcode: barcode,
        onStep: (int step) {
          scan.step = PhotoAnalyzer.steps[step.clamp(0, PhotoAnalyzer.steps.length - 1)];
          notifyListeners();
        },
      );
      // Never flash: the row stays at least this long.
      final Duration seen = DateTime.now().difference(scan.startedAt);
      const Duration minimum = Duration(milliseconds: 1600);
      if (seen < minimum) {
        await Future<void>.delayed(minimum - seen);
      }
      scan.analysis = analysis;
    } catch (_) {
      scan.failed = true;
    } finally {
      ticker.cancel();
      scan.progress = 1.0;
      // The row fills in: a two-beat tap for an answer, two firm beats when
      // nothing could be read.
      if (scan.analysis != null && !scan.analysis!.isEmpty) {
        Haptics.success();
      } else {
        Haptics.warning();
      }
      notifyListeners();
    }
  }

  @visibleForTesting
  void resetForTest() => _scans.clear();
}
