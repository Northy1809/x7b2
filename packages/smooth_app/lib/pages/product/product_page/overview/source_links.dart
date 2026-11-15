import 'package:flutter/material.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/helpers/launch_url_helper.dart';
import 'package:smooth_app/services/score_types.dart';

/// Tappable list of sources ("Read the source") that open in the browser.
class SourceLinks extends StatelessWidget {
  const SourceLinks(this.sources, {this.dense = false});

  final List<SourceLink> sources;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final SourceLink s in sources)
          InkWell(
            onTap: () => LaunchUrlHelper.launchURL(s.url),
            borderRadius: ANGULAR_BORDER_RADIUS,
            child: Padding(
              padding: EdgeInsetsDirectional.symmetric(
                vertical: dense ? 4.0 : 6.0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 2.0),
                    child: Icon(
                      Icons.open_in_new,
                      size: 16.0,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: SMALL_SPACE),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: s.title,
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(
                            text: '  ${s.host}',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12.0,
                            ),
                          ),
                        ],
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
