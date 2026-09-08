import 'package:flutter/material.dart';

/// One labelled area: a caption row with optional controls on the right, and
/// a field beneath it.
///
/// The controls are handed in already built, and the caller decides whether
/// they appear: per the interface rules they are only visible when that box
/// has content.
class LabelledBox extends StatelessWidget {
  const LabelledBox({
    required this.label,
    required this.child,
    this.actions = const <Widget>[],
    this.footer,
    this.expand = false,
    super.key,
  });

  final String label;
  final Widget child;
  final List<Widget> actions;

  /// Helper or error text shown under the field.
  final Widget? footer;

  /// Whether the field should fill the space this box is given.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final header = Row(
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.4,
          ),
        ),
        const Spacer(),
        // A fixed-height slot so the layout does not jump when the controls
        // appear and disappear with the box's content.
        SizedBox(
          height: 32,
          child: Row(mainAxisSize: MainAxisSize.min, children: actions),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        header,
        const SizedBox(height: 4),
        if (expand) Expanded(child: child) else child,
        if (footer != null) ...<Widget>[
          const SizedBox(height: 6),
          footer!,
        ],
      ],
    );
  }
}

/// A compact icon button sized for the header row of a [LabelledBox].
class BoxAction extends StatelessWidget {
  const BoxAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.colour,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 19),
      tooltip: tooltip,
      onPressed: onPressed,
      color: colour,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 30),
      splashRadius: 18,
    );
  }
}
