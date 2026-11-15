import 'package:flutter/material.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/themes/brand_colors.dart';

/// "Analyzing…" while a scan or photo is read: a spinner, the steps done so
/// far and the one running, and faint bars where the answer will land.
class AnalyzingCard extends StatelessWidget {
  const AnalyzingCard({
    required this.title,
    required this.steps,
    required this.step,
    super.key,
  });

  final String title;
  final List<String> steps;

  /// Index of the running step; the ones before are done.
  final int step;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final int pct = steps.isEmpty
        ? 0
        : ((step + 0.5) / steps.length * 100).round().clamp(5, 95);
    return Semantics(
      liveRegion: true,
      label: '$title. ${step < steps.length ? steps[step] : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          LARGE_SPACE,
          SMALL_SPACE,
          LARGE_SPACE,
          LARGE_SPACE,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox.square(
                  dimension: 56.0,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(end: pct / 100),
                        duration: const Duration(milliseconds: 500),
                        builder: (_, double v, _) => CircularProgressIndicator(
                          value: v,
                          strokeWidth: 5.0,
                          strokeCap: StrokeCap.round,
                          color: BrandColors.indigo,
                          backgroundColor: theme.colorScheme.onSurface
                              .withValues(alpha: 0.08),
                        ),
                      ),
                      Text(
                        '$pct%',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: MEDIUM_SPACE),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '$title…',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        step < steps.length ? steps[step] : '',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: LARGE_SPACE),
            for (int i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 10.0),
                child: Row(
                  children: <Widget>[
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: i < step
                          ? const Icon(
                              Icons.check_circle_rounded,
                              key: ValueKey<int>(1),
                              color: Color(0xFF1E1A22),
                              size: 22.0,
                            )
                          : i == step
                          ? const SizedBox.square(
                              key: ValueKey<int>(2),
                              dimension: 22.0,
                              child: Padding(
                                padding: EdgeInsetsDirectional.all(3.0),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.circle_outlined,
                              key: const ValueKey<int>(3),
                              color: muted.withValues(alpha: 0.4),
                              size: 22.0,
                            ),
                    ),
                    const SizedBox(width: SMALL_SPACE),
                    Text(
                      steps[i],
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: i <= step ? theme.colorScheme.onSurface : muted,
                        fontWeight: i == step
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: SMALL_SPACE),
            const _SkeletonBar(widthFactor: 1.0, height: 84.0),
            const SizedBox(height: SMALL_SPACE),
            const Row(
              children: <Widget>[
                Expanded(child: _SkeletonBar(widthFactor: 1.0, height: 64.0)),
                SizedBox(width: SMALL_SPACE),
                Expanded(child: _SkeletonBar(widthFactor: 1.0, height: 64.0)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatefulWidget {
  const _SkeletonBar({required this.widthFactor, required this.height});

  final double widthFactor;
  final double height;

  @override
  State<_SkeletonBar> createState() => _SkeletonBarState();
}

class _SkeletonBarState extends State<_SkeletonBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color base = Theme.of(context).colorScheme.onSurface;
    return FractionallySizedBox(
      widthFactor: widget.widthFactor,
      alignment: AlignmentDirectional.centerStart,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: base.withValues(alpha: 0.05 + 0.04 * _c.value),
            borderRadius: BorderRadius.circular(20.0),
          ),
        ),
      ),
    );
  }
}
