import 'dart:async';

import 'package:flutter/services.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';

/// The app's vibrations, graded by how much just happened (research/ui/
/// videos/NOTES.md: light for small or repeated input, heavier for bigger
/// moves, a two-beat pattern for a win).
///
/// | Moment                                    | Call        | iOS feel                |
/// |-------------------------------------------|-------------|-------------------------|
/// | A tap on a card, row or button            | [tap]       | light impact            |
/// | Picking one of several (tab, choice, page)| [select]    | selection tick          |
/// | Opening something big (+ menu, camera)    | [open]      | medium impact           |
/// | The shutter                               | [shutter]   | heavy impact            |
/// | A barcode or brand recognised             | [detected]  | medium + light          |
/// | An answer arrives (owner found)           | [success]   | light, then medium      |
/// | Nothing found / failed                    | [warning]   | two medium beats        |
/// | Something removed                         | [remove]    | rigid medium            |
///
/// Every call is a no-op when the user turned haptics off in Profile.
class Haptics {
  const Haptics._();

  /// Test hook: every pattern played, in order.
  static final List<String> debugLog = <String>[];

  /// Set by tests to see what would vibrate without a preferences store.
  static bool? debugEnabledOverride;

  static bool get _enabled {
    if (debugEnabledOverride != null) {
      return debugEnabledOverride!;
    }
    try {
      return UserPreferences.getUserPreferencesSync().hapticFeedbackEnabled;
    } catch (_) {
      // Preferences not loaded yet (first frames, some tests): vibrate.
      return true;
    }
  }

  static void _play(final String name, final List<Future<void> Function()> beats, {Duration gap = Duration.zero}) {
    if (!_enabled) {
      return;
    }
    debugLog.add(name);
    unawaited(() async {
      for (int i = 0; i < beats.length; i++) {
        if (i > 0 && gap > Duration.zero) {
          await Future<void>.delayed(gap);
        }
        await beats[i]();
      }
    }());
  }

  static void tap() => _play('tap', <Future<void> Function()>[HapticFeedback.lightImpact]);

  static void select() => _play('select', <Future<void> Function()>[HapticFeedback.selectionClick]);

  static void open() => _play('open', <Future<void> Function()>[HapticFeedback.mediumImpact]);

  static void shutter() => _play('shutter', <Future<void> Function()>[HapticFeedback.heavyImpact]);

  static void detected() => _play(
    'detected',
    <Future<void> Function()>[HapticFeedback.mediumImpact, HapticFeedback.lightImpact],
    gap: const Duration(milliseconds: 70),
  );

  static void success() => _play(
    'success',
    <Future<void> Function()>[HapticFeedback.lightImpact, HapticFeedback.mediumImpact],
    gap: const Duration(milliseconds: 90),
  );

  static void warning() => _play(
    'warning',
    <Future<void> Function()>[HapticFeedback.mediumImpact, HapticFeedback.mediumImpact],
    gap: const Duration(milliseconds: 120),
  );

  static void remove() => _play('remove', <Future<void> Function()>[HapticFeedback.mediumImpact]);
}
