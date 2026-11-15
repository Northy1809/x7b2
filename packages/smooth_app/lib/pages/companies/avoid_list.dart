import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/pages/product/product_page/overview/owner_section.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/company_logo.dart';

/// The companies the user avoids, as grey Cal AI rows with a way to take
/// each one off the list (with Undo), and the "hide in search" switch.
/// Used on the Companies tab and on its own page (the home's avoid pill).
class AvoidList extends StatelessWidget {
  const AvoidList({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: AvoidedOwners.instance,
      builder: (BuildContext context, _) {
        final List<String> names = AvoidedOwners.instance.names;
        if (names.isEmpty) {
          return Container(
            padding: const EdgeInsetsDirectional.all(16.0),
            decoration: BoxDecoration(
              color: dark ? BrandColors.fillDark : BrandColors.row,
              borderRadius: BorderRadius.circular(18.0),
              border: Border.all(color: dark ? BrandColors.hairlineDark : const Color(0xFFF1F0F6)),
            ),
            child: Row(
              children: <Widget>[
                Icon(CupertinoIcons.nosign, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Text(
                    'Open a company and tap "Avoid this company". Owned then warns you '
                    'whenever you scan one of its products.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          children: <Widget>[
            for (final String n in names) ...<Widget>[
              _AvoidRow(name: n),
              const SizedBox(height: 8.0),
            ],
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 4.0),
              title: const Text('Hide their products in search'),
              value: AvoidedOwners.instance.hideInSearch,
              onChanged: (bool on) {
                Haptics.select();
                unawaited(AvoidedOwners.instance.setHideInSearch(on));
              },
            ),
          ],
        );
      },
    );
  }
}

class _AvoidRow extends StatelessWidget {
  const _AvoidRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return PressScale(
      scale: 0.98,
      onTap: () => openOwnerPage(context, name: name),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(10.0, 10.0, 6.0, 10.0),
        decoration: BoxDecoration(
          color: dark ? BrandColors.fillDark : BrandColors.row,
          borderRadius: BorderRadius.circular(18.0),
          border: Border.all(color: dark ? BrandColors.hairlineDark : const Color(0xFFF1F0F6)),
        ),
        child: Row(
          children: <Widget>[
            CompanyLogo(names: <String>[name], size: 44.0, radius: 12.0),
            const SizedBox(width: 12.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16.0, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Avoided',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13.0,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Stop avoiding $name',
              icon: Icon(CupertinoIcons.xmark_circle_fill, color: theme.colorScheme.onSurfaceVariant),
              onPressed: () {
                Haptics.remove();
                unawaited(AvoidedOwners.instance.remove(name));
                final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('No longer avoiding $name'),
                    behavior: SnackBarBehavior.floating,
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () => unawaited(AvoidedOwners.instance.add(name)),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The avoid list on its own page (opened from the home's avoid pill and
/// the + menu).
class AvoidListPage extends StatelessWidget {
  const AvoidListPage({super.key});

  static Future<void> open(final BuildContext context) =>
      Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const AvoidListPage()));

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar.large(
            title: const Text('Companies you avoid'),
            backgroundColor: theme.scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
          ),
          const SliverPadding(
            padding: EdgeInsetsDirectional.fromSTEB(20.0, 4.0, 20.0, 40.0),
            sliver: SliverToBoxAdapter(child: AvoidList()),
          ),
        ],
      ),
    );
  }
}
