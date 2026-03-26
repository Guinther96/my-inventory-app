import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/models/category_model.dart';
import '../../../../data/providers/inventory_provider.dart';
import '../../../common_widgets/app_drawer.dart';
import '../../../common_widgets/app_sidebar.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  String _categoryPathLabel(Category category, Map<String, Category> byId) {
    final visited = <String>{};
    final parts = <String>[category.name];

    var currentParentId = category.parentId;
    while (currentParentId != null && !visited.contains(currentParentId)) {
      visited.add(currentParentId);
      final parent = byId[currentParentId];
      if (parent == null) {
        break;
      }
      parts.insert(0, parent.name);
      currentParentId = parent.parentId;
    }

    return parts.join(' > ');
  }

  Category? _findCategoryById(List<Category> categories, String id) {
    for (final category in categories) {
      if (category.id == id) {
        return category;
      }
    }
    return null;
  }

  bool _wouldCreateCycle({
    required List<Category> allCategories,
    required String currentCategoryId,
    required String candidateParentId,
  }) {
    var cursor = _findCategoryById(allCategories, candidateParentId);
    final visited = <String>{};

    while (cursor != null && !visited.contains(cursor.id)) {
      if (cursor.id == currentCategoryId) {
        return true;
      }
      visited.add(cursor.id);
      final nextParentId = cursor.parentId;
      if (nextParentId == null) {
        return false;
      }
      cursor = _findCategoryById(allCategories, nextParentId);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 950;
    final horizontalPadding = isDesktop ? 24.0 : 14.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: isDesktop ? null : AppBar(title: const Text('Categories')),
      drawer: isDesktop ? null : const AppDrawer(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) const AppSidebar(),
          Expanded(
            child: Consumer<InventoryProvider>(
              builder: (context, inventory, _) {
                final categories = [...inventory.categories]
                  ..sort((a, b) => a.name.compareTo(b.name));
                final categoriesById = <String, Category>{
                  for (final c in categories) c.id: c,
                };

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
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          Text(
                            'Categories produits',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          FilledButton.icon(
                            onPressed: () => _openCategoryDialog(
                              context,
                              categories: categories,
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Nouvelle categorie'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Container(
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
                          child: categories.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.account_tree_outlined,
                                          size: 46,
                                          color: colorScheme.primary,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Aucune categorie pour le moment',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Commencez par creer une categorie racine. Vous pourrez ensuite ajouter des sous-categories.',
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 16),
                                        FilledButton.icon(
                                          onPressed: () => _openCategoryDialog(
                                            context,
                                            categories: categories,
                                          ),
                                          icon: const Icon(Icons.add),
                                          label: const Text(
                                            'Creer la premiere categorie',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: categories.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final category = categories[index];
                                    return ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 6,
                                          ),
                                      leading: CircleAvatar(
                                        backgroundColor: const Color(
                                          0xFFE7F7FC,
                                        ),
                                        foregroundColor: const Color(
                                          0xFF0C7EA5,
                                        ),
                                        child: Text(
                                          category.name.isEmpty
                                              ? '?'
                                              : category.name[0].toUpperCase(),
                                        ),
                                      ),
                                      title: Text(category.name),
                                      subtitle: Text(
                                        '${_categoryPathLabel(category, categoriesById)}\n${category.description ?? 'Aucune description'}',
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.add_link),
                                            tooltip:
                                                'Ajouter une sous-categorie',
                                            onPressed: () =>
                                                _openCategoryDialog(
                                                  context,
                                                  categories: categories,
                                                  parentCategory: category,
                                                ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            onPressed: () =>
                                                _openCategoryDialog(
                                                  context,
                                                  category: category,
                                                  categories: categories,
                                                ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            onPressed: () async {
                                              await inventory.deleteCategory(
                                                category.id,
                                              );
                                            },
                                          ),
                                        ],
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

  Future<void> _openCategoryDialog(
    BuildContext context, {
    Category? category,
    List<Category>? categories,
    Category? parentCategory,
  }) async {
    final inventory = context.read<InventoryProvider>();
    final allCategories = categories ?? [...inventory.categories]
      ..sort((a, b) => a.name.compareTo(b.name));

    final nameController = TextEditingController(text: category?.name ?? '');
    final descController = TextEditingController(
      text: category?.description ?? '',
    );
    String? selectedParentId = parentCategory?.id ?? category?.parentId;
    final isSubCategoryCreation = category == null && parentCategory != null;

    final parentCandidates = allCategories.where((candidate) {
      if (candidate.id == category?.id) {
        return false;
      }

      if (category == null) {
        return true;
      }

      return !_wouldCreateCycle(
        allCategories: allCategories,
        currentCategoryId: category.id,
        candidateParentId: candidate.id,
      );
    }).toList();

    final allById = <String, Category>{for (final c in allCategories) c.id: c};

    await showDialog<void>(
      context: context,
      builder: (context) {
        final title = category == null
            ? (isSubCategoryCreation
                  ? 'Nouvelle sous-categorie'
                  : 'Nouvelle categorie')
            : 'Modifier categorie';
        final mediaQuery = MediaQuery.of(context);
        final availableHeight =
            mediaQuery.size.height - mediaQuery.viewInsets.vertical - 48;
        final dialogMaxHeight = availableHeight < 280 ? 280.0 : availableHeight;

        return AnimatedPadding(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: mediaQuery.viewInsets,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: dialogMaxHeight,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: StatefulBuilder(
                  builder: (context, setDialogState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'Nom'),
                        ),
                        const SizedBox(height: 12),
                        if (isSubCategoryCreation)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F9FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFCEE5FF),
                              ),
                            ),
                            child: Text(
                              'Parent: ${_categoryPathLabel(parentCategory!, allById)}',
                            ),
                          )
                        else
                          DropdownButtonFormField<String?>(
                            value: selectedParentId,
                            decoration: const InputDecoration(
                              labelText: 'Categorie parent',
                            ),
                            items: <DropdownMenuItem<String?>>[
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Aucune (categorie racine)'),
                              ),
                              ...parentCandidates.map(
                                (candidate) => DropdownMenuItem<String?>(
                                  value: candidate.id,
                                  child: Text(
                                    _categoryPathLabel(candidate, allById),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setDialogState(() => selectedParentId = value);
                            },
                          ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: descController,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                          ),
                        ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Annuler'),
                              ),
                              FilledButton(
                                onPressed: () async {
                                  final name = nameController.text.trim();
                                  if (name.isEmpty) {
                                    return;
                                  }

                                  final now = DateTime.now();
                                  await inventory.addOrUpdateCategory(
                                    Category(
                                      id:
                                          category?.id ??
                                          'cat-${now.microsecondsSinceEpoch}',
                                      name: name,
                                      description:
                                          descController.text.trim().isEmpty
                                          ? null
                                          : descController.text.trim(),
                                      parentId: selectedParentId,
                                      createdAt: category?.createdAt ?? now,
                                    ),
                                  );

                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                                child: const Text('Enregistrer'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
