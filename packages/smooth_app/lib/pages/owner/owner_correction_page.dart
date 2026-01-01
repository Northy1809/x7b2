import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/product/product_page/overview/owner_section.dart';
import 'package:smooth_app/pages/product/product_page/overview/product_overview.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/owner_directory.dart';
import 'package:smooth_app/services/owner_overrides.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// "Not right?": the user names the real owner. The correction stays on the
/// phone and wins over the database on every screen. Pops with true when
/// something changed, so the caller can look again.
class OwnerCorrectionPage extends StatefulWidget {
  const OwnerCorrectionPage({
    required this.barcode,
    required this.brands,
    required this.currentOwner,
    this.onLookAgain,
    this.localDb,
    this.ethicsDb,
    super.key,
  });

  final String barcode;
  final String? brands;

  /// What Owned shows now, or null when no owner was found.
  final String? currentOwner;

  /// Opens the online search (brand / photo of the label) instead.
  final VoidCallback? onLookAgain;

  /// For tests; normally the bundled databases.
  final Future<OwnershipLocalDb> Function()? localDb;
  final Future<EthicsDb> Function()? ethicsDb;

  @override
  State<OwnerCorrectionPage> createState() => _OwnerCorrectionPageState();
}

class _OwnerCorrectionPageState extends State<OwnerCorrectionPage> {
  final TextEditingController _controller = TextEditingController();
  OwnerDirectory? _directory;
  List<OwnerRef> _suggestions = const <OwnerRef>[];
  bool _hasCorrection = false;

  String? get _brand {
    return displayBrand(widget.brands);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_init());
    _controller.addListener(_onChanged);
  }

  Future<void> _init() async {
    await OwnerOverrides.instance.load();
    final String? existing = OwnerOverrides.instance.ownerFor(barcode: widget.barcode, brands: widget.brands);
    OwnershipLocalDb? db;
    EthicsDb? ethics;
    try {
      db = await (widget.localDb ?? OwnershipLocalDb.load)();
      ethics = await (widget.ethicsDb ?? EthicsDb.load)();
    } catch (_) {
      // Suggestions are a help, not a need.
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _hasCorrection = existing != null;
      _directory = OwnerDirectory(db, ethics);
    });
    // Editing an earlier correction starts from it, selected so typing replaces it.
    if (existing != null && _controller.text.isEmpty) {
      _controller.value = TextEditingValue(
        text: existing,
        selection: TextSelection(baseOffset: 0, extentOffset: existing.length),
      );
    }
  }

  void _onChanged() {
    final List<OwnerRef> next = _directory?.search(_controller.text, limit: 4) ?? const <OwnerRef>[];
    final bool exact = next.length == 1 && next.first.name.toLowerCase() == _controller.text.trim().toLowerCase();
    setState(() => _suggestions = exact ? const <OwnerRef>[] : next);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _controller.text.trim();
    if (name.isEmpty) {
      return;
    }
    await OwnerOverrides.instance.set(barcode: widget.barcode, brands: widget.brands, owner: name);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _undo() async {
    await OwnerOverrides.instance.remove(barcode: widget.barcode, brands: widget.brands);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String subject = _brand ?? 'this product';
    final TextStyle? muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.4,
    );
    return Scaffold(
      appBar: const CalTopBar(title: 'Correct the owner'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(LARGE_SPACE),
          children: <Widget>[
            const SectionLabel('Owned shows now'),
            const SizedBox(height: SMALL_SPACE),
            Row(
              children: <Widget>[
                OwnerAvatar(name: widget.currentOwner, size: 40.0),
                const SizedBox(width: MEDIUM_SPACE),
                Expanded(
                  child: Text(
                    widget.currentOwner ?? 'No owner found',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: VERY_LARGE_SPACE),
            Text(
              'Who owns $subject?',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: SMALL_SPACE),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: ownedFieldDecoration(theme, hint: 'Company name, e.g. Unilever', icon: Icons.business_rounded),
            ),
            for (final OwnerRef s in _suggestions)
              ListTile(
                contentPadding: EdgeInsetsDirectional.zero,
                leading: OwnerAvatar(name: s.name, size: 32.0),
                title: Text(s.name),
                onTap: () {
                  _controller.text = s.name;
                  _controller.selection = TextSelection.collapsed(offset: s.name.length);
                },
              ),
            const SizedBox(height: MEDIUM_SPACE),
            Text(
              'Saved on this phone only. Owned will show this owner for $subject on every screen.',
              style: muted,
            ),
            const SizedBox(height: LARGE_SPACE),
            ListenableBuilder(
              listenable: _controller,
              builder: (BuildContext context, _) => FilledButton(
                onPressed: _controller.text.trim().isEmpty ? null : _save,
                child: const Text('Save correction'),
              ),
            ),
            if (_hasCorrection) ...<Widget>[
              const SizedBox(height: SMALL_SPACE),
              OutlinedButton(
                onPressed: _undo,
                child: const Text('Remove my correction'),
              ),
            ],
            if (widget.onLookAgain != null) ...<Widget>[
              const SizedBox(height: SMALL_SPACE),
              TextButton.icon(
                onPressed: widget.onLookAgain,
                icon: const Icon(Icons.search),
                label: const Text('Not sure? Look it up by brand or label'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The app's text field: rounded like its buttons, filled, with an icon.
InputDecoration ownedFieldDecoration(final ThemeData theme, {required final String hint, final IconData? icon}) {
  OutlineInputBorder border(final Color color, [final double width = 1.0]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16.0),
    borderSide: BorderSide(color: color, width: width),
  );
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: theme.colorScheme.surface,
    prefixIcon: icon == null ? null : Icon(icon),
    border: border(theme.colorScheme.outlineVariant),
    enabledBorder: border(theme.colorScheme.outlineVariant),
    focusedBorder: border(theme.colorScheme.primary, 2.0),
  );
}
