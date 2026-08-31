import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// iOS-style "inset grouped" section: an optional upper-case header, a rounded
/// card holding [children] separated by hairline dividers, and an optional
/// footer note. Put ListTile / SwitchListTile rows inside.
class IosListSection extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> children;

  const IosListSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(Divider(
          height: 0.5,
          thickness: 0.5,
          indent: 16,
          color: theme.dividerColor,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 7),
            child: Text(
              header!.toUpperCase(),
              style: TextStyle(
                  fontSize: 13, color: muted, letterSpacing: 0.2),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: rows),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 7, 20, 0),
            child: Text(
              footer!,
              style: TextStyle(fontSize: 12.5, color: muted),
            ),
          ),
      ],
    );
  }
}

/// Centered placeholder for empty screens: a large muted icon, a title and an
/// optional subtitle / action button.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: muted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Platform-adaptive spinner — the iOS "spokes" indicator so loading states
/// read as native rather than the Material ring.
class AdaptiveProgress extends StatelessWidget {
  final double? radius;

  const AdaptiveProgress({super.key, this.radius});

  @override
  Widget build(BuildContext context) {
    return CupertinoActivityIndicator(radius: radius ?? 12);
  }
}
