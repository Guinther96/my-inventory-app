import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/providers/inventory_provider.dart';
import '../../../common_widgets/app_drawer.dart';
import '../../../common_widgets/app_sidebar.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String? _selectedProductId;
  String _movementType = 'entry';
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 950;
    final horizontalPadding = isDesktop ? 24.0 : 14.0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: isDesktop
          ? null
          : AppBar(title: const Text('Mouvements de stock')),
      drawer: isDesktop ? null : const AppDrawer(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) const AppSidebar(),
          Expanded(
            child: Consumer<InventoryProvider>(
              builder: (context, inventory, _) {
                final products = [...inventory.products]
                  ..sort((a, b) => a.name.compareTo(b.name));

                if (products.isNotEmpty &&
                    (_selectedProductId == null ||
                        inventory.findProductById(_selectedProductId!) ==
                            null)) {
                  _selectedProductId = products.first.id;
                }

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    20,
                    horizontalPadding,
                    18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestion des mouvements',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withValues(alpha: 0.08),
                              blurRadius: 18,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Nouveau mouvement',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: _selectedProductId,
                                decoration: const InputDecoration(
                                  labelText: 'Produit',
                                ),
                                items: products
                                    .map(
                                      (p) => DropdownMenuItem<String>(
                                        value: p.id,
                                        child: Text(
                                          '${p.name} (Stock: ${p.quantityInStock})',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  setState(() => _selectedProductId = value);
                                },
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                value: _movementType,
                                decoration: const InputDecoration(
                                  labelText: 'Type de mouvement',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'entry',
                                    child: Text('Entree'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'exit',
                                    child: Text('Sortie'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'adjustment',
                                    child: Text('Ajustement (valeur finale)'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _movementType = value);
                                  }
                                },
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _quantityController,
                                decoration: InputDecoration(
                                  labelText: _movementType == 'adjustment'
                                      ? 'Nouvelle quantite en stock'
                                      : 'Quantite',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _notesController,
                                decoration: const InputDecoration(
                                  labelText: 'Notes',
                                ),
                              ),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed: () async {
                                  final selectedId = _selectedProductId;
                                  final quantity =
                                      int.tryParse(
                                        _quantityController.text.trim(),
                                      ) ??
                                      0;
                                  if (selectedId == null || quantity <= 0) {
                                    return;
                                  }

                                  await inventory.addStockMovement(
                                    productId: selectedId,
                                    movementType: _movementType,
                                    quantity: quantity,
                                    notes: _notesController.text.trim().isEmpty
                                        ? null
                                        : _notesController.text.trim(),
                                  );

                                  _quantityController.clear();
                                  _notesController.clear();
                                },
                                icon: const Icon(Icons.save),
                                label: const Text('Enregistrer mouvement'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Historique recent',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withValues(
                                  alpha: 0.08,
                                ),
                                blurRadius: 18,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ListView.separated(
                            itemCount: inventory.recentMovements.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final movement = inventory.recentMovements[index];
                              final productName = inventory.productNameFor(
                                movement.productId,
                              );

                              final typeLabel = switch (movement.movementType) {
                                'entry' => 'Entree',
                                'exit' => 'Sortie',
                                _ => 'Ajustement',
                              };

                              final sign = movement.movementType == 'exit'
                                  ? '-'
                                  : '+';

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      movement.movementType == 'exit'
                                      ? colorScheme.errorContainer
                                      : colorScheme.tertiaryContainer,
                                  child: Icon(
                                    movement.movementType == 'exit'
                                        ? Icons.arrow_upward
                                        : Icons.arrow_downward,
                                    color: movement.movementType == 'exit'
                                        ? colorScheme.error
                                        : colorScheme.tertiary,
                                  ),
                                ),
                                title: Text('$typeLabel - $productName'),
                                subtitle: Text(
                                  '${movement.createdAt.day.toString().padLeft(2, '0')}/${movement.createdAt.month.toString().padLeft(2, '0')}/${movement.createdAt.year}',
                                ),
                                trailing: Text(
                                  '$sign${movement.quantity}',
                                  style: TextStyle(
                                    color: movement.movementType == 'exit'
                                        ? colorScheme.error
                                        : colorScheme.tertiary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
