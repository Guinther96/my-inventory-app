import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';

enum CustomButtonVariant { primary, secondary }

/// Bouton standard de l'app: radius 14, hauteur 48, animation hover/press
/// legere, ombre douce sur le variant primaire. Le variant secondaire est
/// fond blanc + bordure grise. Purement presentationnel: le callback
/// [onPressed] porte toute la logique (inchangee, fournie par l'appelant).
class CustomButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final CustomButtonVariant variant;
  final bool fullWidth;

  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = CustomButtonVariant.primary,
    this.fullWidth = false,
  });

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _isPrimary => widget.variant == CustomButtonVariant.primary;
  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Survol: leger assombrissement de la primary courante (fonctionne aussi
    // bien pour le bleu clair que pour le bleu plus lumineux du mode sombre).
    final hoverPrimary = Color.alphaBlend(
      Colors.black.withValues(alpha: 0.10),
      colorScheme.primary,
    );

    final backgroundColor = !_enabled
        ? (_isPrimary
              ? colorScheme.primary.withValues(alpha: 0.4)
              : colorScheme.surface)
        : _isPrimary
        ? (_hovered ? hoverPrimary : colorScheme.primary)
        : colorScheme.surface;

    final foregroundColor = _isPrimary ? Colors.white : colorScheme.onSurface;

    final border = _isPrimary
        ? null
        : Border.all(
            color: _hovered ? colorScheme.primary : colorScheme.outlineVariant,
          );

    final content = Row(
      mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 18, color: foregroundColor),
          const SizedBox(width: 8),
        ],
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: foregroundColor,
          ),
        ),
      ],
    );

    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            height: 48,
            width: widget.fullWidth ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: AppRadius.buttonAll,
              border: border,
              boxShadow: _isPrimary && _enabled
                  ? [
                      BoxShadow(
                        color: colorScheme.primary.withValues(
                          alpha: _hovered ? 0.32 : 0.22,
                        ),
                        blurRadius: _hovered ? 18 : 12,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );
  }
}
