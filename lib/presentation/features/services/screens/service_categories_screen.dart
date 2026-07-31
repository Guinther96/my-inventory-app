import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/models/service_category_model.dart';
import '../../../../data/models/service_model.dart';
import '../../../../services/service_orders/service_category_service.dart';
import '../../../../services/service_orders/service_service.dart';
import '../../../common_widgets/app_drawer.dart';
import '../../../common_widgets/app_sidebar.dart';

/// Gestion des categories de services (manager uniquement), calquee sur
/// `categories_screen.dart` (produits) mais sans hierarchie parent/enfant:
/// le catalogue de services reste plat par categorie (Hair/Beauty/Spa...).
class ServiceCategoriesScreen extends StatefulWidget {
  const ServiceCategoriesScreen({super.key});

  @override
  State<ServiceCategoriesScreen> createState() =>
      _ServiceCategoriesScreenState();
}

class _ServiceCategoriesScreenState extends State<ServiceCategoriesScreen> {
  final ServiceCategoryService _categoryService = ServiceCategoryService();
  final ServiceService _serviceService = ServiceService();

  bool _isLoading = true;
  String? _error;
  List<ServiceCategory> _categories = const <ServiceCategory>[];
  List<Service> _services = const <Service>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _categoryService.fetchCategories(),
        _serviceService.fetchServices(activeOnly: false),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _categories = (results[0] as List<ServiceCategory>)
          ..sort((a, b) => a.name.compareTo(b.name));
        _services = results[1] as List<Service>;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  int _serviceCountFor(String categoryId) =>
      _services.where((s) => s.categoryId == categoryId).length;

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go('/beauty/services');
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openCategoryDialog({ServiceCategory? category}) async {
    final nameController = TextEditingController(text: category?.name ?? '');
    final descController = TextEditingController(
      text: category?.description ?? '',
    );
    final imageUrlController = TextEditingController(
      text: category?.imageUrl ?? '',
    );
    var active = category?.isActive ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                category == null
                    ? 'Nouvelle categorie de services'
                    : 'Modifier categorie',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nom (ex: Hair Services)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: imageUrlController,
                      decoration: const InputDecoration(
                        labelText: 'URL image/icone (optionnel)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      value: active,
                      onChanged: (value) => setDialogState(() => active = value),
                      title: const Text('Active'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) {
      return;
    }

    final name = nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Le nom de la categorie est obligatoire.');
      return;
    }

    try {
      final upserted = await _categoryService.upsertCategory(
        ServiceCategory(
          id: category?.id ?? '',
          companyId: category?.companyId ?? '',
          name: name,
          description: descController.text.trim().isEmpty
              ? null
              : descController.text.trim(),
          imageUrl: imageUrlController.text.trim().isEmpty
              ? null
              : imageUrlController.text.trim(),
          isActive: active,
          createdAt: category?.createdAt ?? DateTime.now(),
        ),
      );

      if (!mounted) {
        return;
      }
      setState(() {
        final idx = _categories.indexWhere((c) => c.id == upserted.id);
        if (idx >= 0) {
          _categories = [..._categories]..[idx] = upserted;
        } else {
          _categories = [..._categories, upserted];
        }
        _categories.sort((a, b) => a.name.compareTo(b.name));
      });
    } catch (e) {
      _showMessage('Erreur sauvegarde: $e');
    }
  }

  Future<void> _deleteCategory(ServiceCategory category) async {
    final count = _serviceCountFor(category.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer categorie'),
        content: Text(
          count > 0
              ? 'Confirmer la suppression de "${category.name}" ? '
                    '$count service(s) deviendront sans categorie.'
              : 'Confirmer la suppression de "${category.name}" ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _categoryService.deleteCategory(category.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _categories = _categories.where((c) => c.id != category.id).toList();
      });
    } catch (e) {
      _showMessage('Erreur suppression: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 950;
    final horizontalPadding = isDesktop ? 24.0 : 14.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: isDesktop
          ? null
          : AppBar(title: const Text('Categories de services')),
      drawer: isDesktop ? null : const AppDrawer(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) const AppSidebar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  20,
                  horizontalPadding,
                  18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isDesktop)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _goBack,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Retour'),
                        ),
                      ),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        Text(
                          'Categories de services',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () => _openCategoryDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('Nouvelle categorie'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Card(
                        color: const Color(0xFFFFF3E0),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_error!),
                        ),
                      ),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _categories.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.category_outlined,
                                    size: 46,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Aucune categorie pour le moment',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Ex: Hair Services, Beauty Services, Spa Services.',
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 260,
                                    mainAxisSpacing: 14,
                                    crossAxisSpacing: 14,
                                    mainAxisExtent: 170,
                                  ),
                              itemCount: _categories.length,
                              itemBuilder: (context, index) {
                                final category = _categories[index];
                                return _ServiceCategoryCard(
                                  category: category,
                                  serviceCount: _serviceCountFor(category.id),
                                  onEdit: () =>
                                      _openCategoryDialog(category: category),
                                  onDelete: () => _deleteCategory(category),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCategoryCard extends StatelessWidget {
  final ServiceCategory category;
  final int serviceCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServiceCategoryCard({
    required this.category,
    required this.serviceCount,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                    image: category.imageUrl == null
                        ? null
                        : DecorationImage(
                            image: NetworkImage(category.imageUrl!),
                            fit: BoxFit.cover,
                            onError: (exception, stackTrace) {},
                          ),
                  ),
                  alignment: Alignment.center,
                  child: category.imageUrl == null
                      ? Icon(
                          Icons.spa_outlined,
                          color: colorScheme.onPrimaryContainer,
                        )
                      : null,
                ),
                const Spacer(),
                if (!category.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Inactive',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '$serviceCount service${serviceCount > 1 ? 's' : ''}',
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withValues(
                  alpha: 0.65,
                ),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Modifier'),
                  ),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
