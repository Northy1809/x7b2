import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';

/// Cal AI's page furniture (16/11 2026), so no screen falls back to the old
/// Material / Open Food Facts look:
/// - pushed pages: a round grey back button and a centred title
///   ([CalTopBar]);
/// - tab pages: a big bold title on the left ([CalLargeTitle]);
/// - settings: white cards of rows with line icons and chevrons
///   ([CalGroup], [CalNavRow], [CalSwitchRow]);
/// - a grey rounded search field ([CalSearchField]), grey pills
///   ([CalPill]), an ink spinner ([CalLoader]) and a calm empty state
///   ([CalEmpty]).
/// Sizes follow research/ui/CALAI.md (24 pt margins, 20 pt section titles).

/// Side margin of every Cal page.
const double kCalSide = 24.0;

bool _dark(final BuildContext context) => Theme.of(context).brightness == Brightness.dark;

/// The grey of rows, fields and pills.
Color calFill(final BuildContext context) => _dark(context) ? BrandColors.fillDark : BrandColors.fill;

/// The grey of list rows ("Recently uploaded").
Color calRow(final BuildContext context) => _dark(context) ? BrandColors.fillDark : BrandColors.row;

/// Hairlines between rows.
Color calHairline(final BuildContext context) => _dark(context) ? BrandColors.hairlineDark : BrandColors.hairline;

/// Grey list row: #F9F8FD with a faint border and 18 pt corners.
BoxDecoration calRowDecoration(final BuildContext context, {final double radius = 18.0}) => BoxDecoration(
  color: calRow(context),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: _dark(context) ? BrandColors.hairlineDark : const Color(0xFFF1F0F6)),
);

/// A round grey button with a line icon (Cal AI's back arrow, close, more).
class CalRoundButton extends StatelessWidget {
  const CalRoundButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.size = 40.0,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    excludeSemantics: true,
    child: PressScale(
      scale: 0.92,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: calFill(context), shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.45, color: Theme.of(context).colorScheme.onSurface),
      ),
    ),
  );
}

/// The top of a pushed page: round grey back arrow on the left, the title
/// centred, an optional action on the right. White, no line under it.
class CalTopBar extends StatelessWidget implements PreferredSizeWidget {
  const CalTopBar({this.title, this.trailing, this.onBack, this.showBack = true, super.key});

  final String? title;
  final Widget? trailing;

  /// Defaults to closing the page.
  final VoidCallback? onBack;
  final bool showBack;

  static const double height = 56.0;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 16.0),
            child: NavigationToolbar(
              middleSpacing: 12.0,
              leading: showBack
                  ? CalRoundButton(
                      icon: CupertinoIcons.arrow_left,
                      tooltip: 'Back',
                      onTap: onBack ?? () => Navigator.of(context).maybePop(),
                    )
                  : null,
              middle: title == null
                  ? null
                  : Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 17.0,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                      ),
                    ),
              trailing: trailing,
            ),
          ),
        ),
      ),
    );
  }
}

/// The big title at the top of a tab ("Companies", "Search", "Profile").
class CalLargeTitle extends StatelessWidget {
  const CalLargeTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: Theme.of(context).textTheme.displayLarge?.copyWith(
        fontSize: 30.0,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
    ),
  );
}

/// A section title ("Recently scanned", 20 pt semibold) with an optional
/// small action on the right ("See all", "Clear").
class CalSectionTitle extends StatelessWidget {
  const CalSectionTitle(this.text, {this.action, this.onAction, super.key});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              text,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20.0,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.45,
              ),
            ),
          ),
        ),
        if (action != null)
          PressScale(
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 6.0),
              child: Text(
                action!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15.0,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Cal AI's search field: a grey rounded box with a magnifier, the hint in
/// light grey, and a clear button while there is text.
class CalSearchField extends StatefulWidget {
  const CalSearchField({
    required this.controller,
    this.focusNode,
    this.hint = 'Search',
    this.autofocus = false,
    this.onSubmitted,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<CalSearchField> createState() => _CalSearchFieldState();
}

class _CalSearchFieldState extends State<CalSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(CalSearchField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      height: 48.0,
      decoration: BoxDecoration(color: calFill(context), borderRadius: BorderRadius.circular(14.0)),
      padding: const EdgeInsetsDirectional.only(start: 14.0, end: 6.0),
      child: Row(
        children: <Widget>[
          Icon(CupertinoIcons.search, size: 20.0, color: muted),
          const SizedBox(width: 10.0),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              onSubmitted: widget.onSubmitted,
              onChanged: widget.onChanged,
              cursorColor: theme.colorScheme.onSurface,
              style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17.0, letterSpacing: -0.3),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: widget.hint,
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 17.0,
                  letterSpacing: -0.3,
                  color: _dark(context) ? BrandColors.mutedDark : BrandColors.faint,
                ),
              ),
            ),
          ),
          if (widget.controller.text.isNotEmpty)
            Semantics(
              button: true,
              label: 'Clear',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Haptics.tap();
                  widget.controller.clear();
                  widget.onChanged?.call('');
                  widget.focusNode?.requestFocus();
                },
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(8.0),
                  child: Icon(
                    CupertinoIcons.xmark_circle_fill,
                    size: 20.0,
                    color: _dark(context) ? BrandColors.mutedDark : BrandColors.faint,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A grey pill: a brand, a category, a filter. [selected] turns it ink.
class CalPill extends StatelessWidget {
  const CalPill({required this.label, this.icon, this.selected = false, this.onTap, super.key});

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color back = selected ? theme.colorScheme.onSurface : calFill(context);
    final Color fore = selected ? theme.colorScheme.surface : theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: PressScale(
        scale: 0.95,
        feedback: Haptics.select,
        onTap: onTap,
        child: AnimatedContainer(
          duration: CalMotion.select,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 14.0, vertical: 9.0),
          decoration: BoxDecoration(color: back, borderRadius: BorderRadius.circular(999.0)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 15.0, color: fore),
                const SizedBox(width: 6.0),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 15.0,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                    color: fore,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cal AI's waiting state: an ink arc turning on a light track (the same
/// ring as the scores), instead of Material's spinner.
class CalLoader extends StatefulWidget {
  const CalLoader({this.size = 28.0, this.stroke = 3.0, this.label, super.key});

  final double size;
  final double stroke;

  /// Grey text under the ring ("Looking up the product…").
  final String? label;

  @override
  State<CalLoader> createState() => _CalLoaderState();
}

class _CalLoaderState extends State<CalLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget ring = Semantics(
      label: widget.label ?? 'Loading',
      excludeSemantics: true,
      child: RotationTransition(
        turns: _c,
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: CalRingPainter(
              fraction: 0.28,
              color: theme.colorScheme.onSurface,
              track: calHairline(context),
              stroke: widget.stroke,
            ),
          ),
        ),
      ),
    );
    if (widget.label == null) {
      return ring;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ring,
        const SizedBox(height: 14.0),
        Text(
          widget.label!,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15.0, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// A calm empty or error state: a line icon in a grey circle, a title,
/// a grey line, and an optional ink button.
class CalEmpty extends StatelessWidget {
  const CalEmpty({
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 32.0, vertical: 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 64.0,
            height: 64.0,
            decoration: BoxDecoration(color: calFill(context), shape: BoxShape.circle),
            child: Icon(icon, size: 28.0, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 16.0),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(fontSize: 18.0, fontWeight: FontWeight.w600, letterSpacing: -0.4),
          ),
          if (body != null) ...<Widget>[
            const SizedBox(height: 6.0),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 15.0,
                height: 1.35,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: 20.0),
            FilledButton(
              onPressed: onAction == null
                  ? null
                  : () {
                      Haptics.tap();
                      onAction!();
                    },
              style: FilledButton.styleFrom(minimumSize: const Size(160.0, 48.0)),
              child: Text(action!),
            ),
          ],
        ],
      ),
    );
  }
}

/// A white card of rows with hairlines between them, and an optional small
/// grey heading above it: Cal AI's settings groups.
class CalGroup extends StatelessWidget {
  const CalGroup({required this.children, this.title, super.key});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 54.0),
            child: Container(height: 1.0, color: calHairline(context)),
          ),
        );
      }
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4.0, bottom: 8.0),
            child: Semantics(
              header: true,
              child: Text(
                title!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15.0,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        CalCard(
          padding: EdgeInsetsDirectional.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20.0),
            child: Column(children: rows),
          ),
        ),
      ],
    );
  }
}

/// Greys while a finger is down (rows inside a card do not shrink).
class _RowPress extends StatefulWidget {
  const _RowPress({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_RowPress> createState() => _RowPressState();
}

class _RowPressState extends State<_RowPress> {
  bool _down = false;

  void _set(final bool v) {
    if (mounted && _down != v) {
      setState(() => _down = v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: enabled
          ? () {
              Haptics.tap();
              widget.onTap!();
            }
          : null,
      child: AnimatedContainer(
        duration: CalMotion.select,
        color: _down ? calFill(context) : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}

/// One row of a [CalGroup]: line icon, title (and a grey line under it),
/// a grey value on the right and a chevron.
class CalNavRow extends StatelessWidget {
  const CalNavRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.trailing,
    this.chevron = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: onTap != null,
      child: _RowPress(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56.0),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(18.0, 12.0, 14.0, 12.0),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 21.0, color: theme.colorScheme.onSurface),
                const SizedBox(width: 15.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16.0, letterSpacing: -0.3),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(top: 2.0),
                          child: Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, height: 1.3, color: muted),
                          ),
                        ),
                    ],
                  ),
                ),
                if (value != null) ...<Widget>[
                  const SizedBox(width: 8.0),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150.0),
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15.0, color: muted),
                    ),
                  ),
                ],
                if (trailing != null) ...<Widget>[const SizedBox(width: 8.0), trailing!],
                if (chevron && onTap != null) ...<Widget>[
                  const SizedBox(width: 6.0),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 15.0,
                    color: _dark(context) ? BrandColors.mutedDark : BrandColors.faint,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A [CalGroup] row with an iOS switch in ink.
class CalSwitchRow extends StatelessWidget {
  const CalSwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: CalNavRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      chevron: false,
      onTap: () => onChanged(!value),
      trailing: CupertinoSwitch(
        value: value,
        activeTrackColor: Theme.of(context).colorScheme.onSurface,
        onChanged: onChanged,
      ),
    ),
  );
}

/// A white sheet from the bottom with a title and Cal choices; returns the
/// chosen value. Used for Appearance and similar one-of-a-few settings.
Future<T?> showCalChoices<T>({
  required final BuildContext context,
  required final String title,
  required final List<(T, String)> choices,
  required final T selected,
}) => showModalBottomSheet<T>(
  context: context,
  useRootNavigator: true,
  showDragHandle: true,
  builder: (BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(kCalSide, 0.0, kCalSide, 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 22.0,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16.0),
          for (final (T value, String label) in choices) ...<Widget>[
            CalOption(
              selected: value == selected,
              onTap: () => Navigator.of(context).pop(value),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(label)),
                  if (value == selected) const Icon(CupertinoIcons.checkmark_alt, size: 20.0),
                ],
              ),
            ),
            const SizedBox(height: 10.0),
          ],
        ],
      ),
    ),
  ),
);
