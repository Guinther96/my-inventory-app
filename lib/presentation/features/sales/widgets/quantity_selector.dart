import 'package:flutter/material.dart';

/// Selecteur de quantite +/- borne a [1, maxQuantity].
/// Generique: utilise aussi bien pour un produit simple qu'une variante.
class QuantitySelector extends StatelessWidget {
  final int quantity;
  final int maxQuantity;
  final ValueChanged<int> onChanged;

  const QuantitySelector({
    super.key,
    required this.quantity,
    required this.maxQuantity,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canDecrement = quantity > 1;
    final canIncrement = quantity < maxQuantity;

    return Container(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? theme.cardColor
            : const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: canDecrement ? () => onChanged(quantity - 1) : null,
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: canIncrement ? () => onChanged(quantity + 1) : null,
          ),
        ],
      ),
    );
  }
}
