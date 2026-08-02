import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import 'custom_button.dart';
import 'status_badge.dart';

/// Carte produit standard (image, nom, categorie, stock, prix, badge,
/// bouton d'action), utilisee par la grille catalogue de l'ecran Ventes.
/// L'image est fournie par l'appelant (deja gere ailleurs: data-uri,
/// reseau, fallback degrade) plutot que reimplementee ici, pour ne pas
/// dupliquer cette logique existante.
class ProductCard extends StatefulWidget {
  final Widget image;
  final String name;
  final String categoryName;
  final String stockLabel;
  final String priceLabel;
  final String badgeLabel;
  final StatusBadgeType badgeType;
  final String actionLabel;
  final VoidCallback? onAdd;

  const ProductCard({
    super.key,
    required this.image,
    required this.name,
    required this.categoryName,
    required this.stockLabel,
    required this.priceLabel,
    required this.badgeLabel,
    required this.badgeType,
    required this.actionLabel,
    required this.onAdd,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hovered ? 0.09 : 0.05),
              blurRadius: _hovered ? 28 : 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        transform: _hovered
            ? Matrix4.translationValues(0.0, -3.0, 0.0)
            : Matrix4.identity(),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  StatusBadge(label: widget.badgeLabel, type: widget.badgeType),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(child: Center(child: widget.image)),
              const SizedBox(height: 10),
              Text(
                widget.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.stockLabel,
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Text(
                widget.priceLabel,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              CustomButton(
                label: widget.actionLabel,
                onPressed: widget.onAdd,
                fullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
