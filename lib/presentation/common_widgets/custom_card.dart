import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

/// Carte standard de l'app: radius 20, padding 20, fond blanc (surface),
/// bordure legere, ombre douce (blur 25, opacite ~0.05). Si [onTap] est
/// fourni, une legere animation de survol/pression est ajoutee.
class CustomCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const CustomCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl - 4),
    this.onTap,
  });

  @override
  State<CustomCard> createState() => _CustomCardState();
}

class _CustomCardState extends State<CustomCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final interactive = widget.onTap != null;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: interactive && _hovered ? 0.08 : 0.05),
            blurRadius: interactive && _hovered ? 30 : 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      transform: interactive && _hovered
          ? Matrix4.translationValues(0.0, -2.0, 0.0)
          : Matrix4.identity(),
      child: widget.child,
    );

    if (!interactive) {
      return card;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: card,
      ),
    );
  }
}
