import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/category_model.dart';
import '../models/company_model.dart';
import '../models/product_model.dart';
import '../models/stock_movement_model.dart';
import '../../services/company/company_service.dart';
import '../../services/inventory/inventory_supabase_service.dart';

class InventoryProvider extends ChangeNotifier {
  final InventorySupabaseService _inventoryService = InventorySupabaseService();
  final CompanyService _companyService = CompanyService();

  RealtimeChannel? _inventoryRealtimeChannel;
  Timer? _realtimeReloadDebounce;
  bool _isRealtimeReloading = false;
  bool _hasPendingRealtimeReload = false;

  final List<Product> _products = [];
  final List<Category> _categories = [];
  final List<StockMovement> _movements = [];

  bool _isLoading = false;
  bool _isInitialized = false;
  String? _companyId;
  String _companyName = 'Mon entreprise';
  String? _companyEmail;
  CompanyStatus _companyStatus = CompanyStatus.active;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get companyId => _companyId;
  String get companyName => _companyName;
  String? get companyEmail => _companyEmail;
  CompanyStatus get companyStatus => _companyStatus;
  bool get hasActiveCompany => _companyStatus == CompanyStatus.active;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => Supabase.instance.client.auth.currentUser != null;

  List<Product> get products => List.unmodifiable(_products);
  List<Category> get categories => List.unmodifiable(_categories);
  List<StockMovement> get movements => List.unmodifiable(_movements);

  List<Product> get lowStockProducts =>
      _products.where((p) => p.quantityInStock <= p.minStockAlert).toList();

  int get totalProducts => _products.length;
  int get totalItemsInStock =>
      _products.fold(0, (sum, p) => sum + p.quantityInStock);

  double get totalStockValue =>
      _products.fold(0, (sum, p) => sum + (p.price * p.quantityInStock));

  List<StockMovement> get recentMovements {
    final sorted = [..._movements]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(10).toList();
  }

  Future<void> initialize({bool forceRefresh = false}) async {
    if (_isInitialized && !forceRefresh) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        _clearRealtimeResources();
        _clearCollections();
        _companyId = null;
        _companyName = 'Mon entreprise';
        _companyEmail = null;
        _companyStatus = CompanyStatus.active;
        _isInitialized = true;
        return;
      }

      _companyId = await _companyService.ensureCurrentCompanyId();

      if (_companyId == null) {
        _clearRealtimeResources();
        _clearCollections();
        _companyName = 'Mon entreprise';
        _companyEmail = null;
        _companyStatus = CompanyStatus.active;
        _isInitialized = true;
        return;
      }

      _companyName =
          await _companyService.fetchCompanyName(_companyId!) ??
          'Mon entreprise';

      _companyEmail = await _companyService.fetchCompanyEmail(_companyId!);

      _companyStatus = await _companyService.fetchCompanyStatus(_companyId!);

      await _reloadRemoteData();
      _configureRealtime(_companyId!);
      _isInitialized = true;
    } catch (e) {
      _errorMessage = e.toString();
      _clearCollections();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Product? findProductById(String id) {
    try {
      return _products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Category? findCategoryById(String id) {
    try {
      return _categories.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> addOrUpdateCategory(Category category) async {
    final tenantId = _companyId;
    if (tenantId == null) {
      return;
    }

    final isNew = category.id.trim().isEmpty;
    final saved = await _inventoryService.upsertCategory(
      companyId: tenantId,
      category: category,
      isNew: isNew,
    );

    final index = _categories.indexWhere((c) => c.id == category.id);
    if (index >= 0) {
      _categories[index] = saved;
    } else {
      final savedIndex = _categories.indexWhere((c) => c.id == saved.id);
      if (savedIndex >= 0) {
        _categories[savedIndex] = saved;
      } else {
        _categories.add(saved);
      }
    }

    notifyListeners();
  }

  Future<void> deleteCategory(String categoryId) async {
    final tenantId = _companyId;
    if (tenantId == null) {
      return;
    }

    await _inventoryService.deleteCategory(
      companyId: tenantId,
      categoryId: categoryId,
    );

    _categories.removeWhere((c) => c.id == categoryId);

    for (var i = 0; i < _products.length; i++) {
      final product = _products[i];
      if (product.categoryId == categoryId) {
        _products[i] = product.copyWith(
          categoryId: null,
          updatedAt: DateTime.now(),
        );
      }
    }

    notifyListeners();
  }

  Future<void> addOrUpdateProduct(Product product) async {
    final tenantId = await _resolveCompanyIdOrThrow();

    final isNew = product.id.trim().isEmpty;
    final saved = await _inventoryService.upsertProduct(
      companyId: tenantId,
      product: product,
      isNew: isNew,
    );

    _products.removeWhere((p) => p.id == product.id || p.id == saved.id);
    _products.add(saved.copyWith(updatedAt: DateTime.now()));
    _products.sort((a, b) => a.name.compareTo(b.name));

    notifyListeners();
  }

  Future<String> _resolveCompanyIdOrThrow() async {
    if (_companyId != null && _companyId!.isNotEmpty) {
      return _companyId!;
    }

    _companyId = await _companyService.ensureCurrentCompanyId();
    if (_companyId != null && _companyId!.isNotEmpty) {
      return _companyId!;
    }

    throw Exception(
      'Profil entreprise introuvable. Reconnectez-vous puis reessayez.',
    );
  }

  Future<void> deleteProduct(String productId) async {
    final tenantId = _companyId;
    if (tenantId == null) {
      return;
    }

    await _inventoryService.deleteProduct(
      companyId: tenantId,
      productId: productId,
    );

    _products.removeWhere((p) => p.id == productId);
    _movements.removeWhere((m) => m.productId == productId);

    notifyListeners();
  }

  Future<void> addStockMovement({
    required String productId,
    required String movementType,
    required int quantity,
    String? notes,
  }) async {
    final tenantId = _companyId;
    if (tenantId == null) {
      return;
    }

    final index = _products.indexWhere((p) => p.id == productId);
    if (index < 0) {
      return;
    }

    final result = await _inventoryService.addStockMovement(
      companyId: tenantId,
      productId: productId,
      movementType: movementType,
      quantity: quantity,
      notes: notes,
    );

    final updatedProductRaw = Map<String, dynamic>.from(
      result['product'] as Map,
    );
    _products[index] = Product.fromJson({
      ...updatedProductRaw,
      'quantity_in_stock':
          updatedProductRaw['quantity_in_stock'] ??
          updatedProductRaw['quantity'],
      'min_stock_alert':
          updatedProductRaw['min_stock_alert'] ??
          updatedProductRaw['min_stock'],
    });

    final movementRaw = Map<String, dynamic>.from(result['movement'] as Map);
    _movements.insert(
      0,
      StockMovement.fromJson({
        ...movementRaw,
        'movement_type': movementRaw['movement_type'] ?? movementRaw['type'],
      }),
    );

    notifyListeners();
  }

  Future<void> clearAllData() async {
    final tenantId = _companyId;
    if (tenantId == null) {
      return;
    }

    await _inventoryService.clearCompanyData(tenantId);
    _products.clear();
    _categories.clear();
    _movements.clear();

    await _seedDemoDataRemote(tenantId);
    await _reloadRemoteData();
    notifyListeners();
  }

  String productNameFor(String productId) {
    return findProductById(productId)?.name ?? 'Produit inconnu';
  }

  Future<void> _reloadRemoteData() async {
    final tenantId = _companyId;
    if (tenantId == null) {
      _clearCollections();
      return;
    }

    _categories
      ..clear()
      ..addAll(await _inventoryService.fetchCategories(tenantId));

    _products
      ..clear()
      ..addAll(await _inventoryService.fetchProducts(tenantId));

    _movements
      ..clear()
      ..addAll(await _inventoryService.fetchMovements(tenantId));
  }

  void _configureRealtime(String companyId) {
    final client = Supabase.instance.client;

    final existing = _inventoryRealtimeChannel;
    if (existing != null) {
      client.removeChannel(existing);
      _inventoryRealtimeChannel = null;
    }

    _inventoryRealtimeChannel = client
        .channel('inventory-realtime-$companyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'company_id',
            value: companyId,
          ),
          callback: (_) => _scheduleRealtimeReload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'categories',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'company_id',
            value: companyId,
          ),
          callback: (_) => _scheduleRealtimeReload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'stock_movements',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'company_id',
            value: companyId,
          ),
          callback: (_) => _scheduleRealtimeReload(),
        )
        .subscribe();
  }

  void _scheduleRealtimeReload() {
    if (_companyId == null) {
      return;
    }

    _realtimeReloadDebounce?.cancel();
    _realtimeReloadDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_reloadFromRealtime());
    });
  }

  Future<void> _reloadFromRealtime() async {
    final tenantId = _companyId;
    if (tenantId == null || !isAuthenticated) {
      return;
    }

    if (_isRealtimeReloading) {
      _hasPendingRealtimeReload = true;
      return;
    }

    _isRealtimeReloading = true;

    try {
      await _reloadRemoteData();
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    } finally {
      _isRealtimeReloading = false;
      if (_hasPendingRealtimeReload) {
        _hasPendingRealtimeReload = false;
        _scheduleRealtimeReload();
      }
    }
  }

  void _clearRealtimeResources() {
    _realtimeReloadDebounce?.cancel();
    _realtimeReloadDebounce = null;
    _isRealtimeReloading = false;
    _hasPendingRealtimeReload = false;

    final channel = _inventoryRealtimeChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
      _inventoryRealtimeChannel = null;
    }
  }

  Future<void> _seedDemoDataRemote(String tenantId) async {
    final medecine = Category(
      id: '',
      name: 'Medicaments',
      description: null,
      createdAt: DateTime.now(),
    );
    final hygiene = Category(
      id: '',
      name: 'Hygiene',
      description: null,
      createdAt: DateTime.now(),
    );

    final savedMedicine = await _inventoryService.upsertCategory(
      companyId: tenantId,
      category: medecine,
      isNew: true,
    );
    final savedHygiene = await _inventoryService.upsertCategory(
      companyId: tenantId,
      category: hygiene,
      isNew: true,
    );

    final aspirin = await _inventoryService.upsertProduct(
      companyId: tenantId,
      product: Product(
        id: '',
        categoryId: savedMedicine.id,
        name: 'Aspirine 500mg',
        description: null,
        barcode: null,
        price: 4.5,
        quantityInStock: 80,
        minStockAlert: 15,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      isNew: true,
    );

    await _inventoryService.upsertProduct(
      companyId: tenantId,
      product: Product(
        id: '',
        categoryId: savedHygiene.id,
        name: 'Gel hydroalcoolique 250ml',
        description: null,
        barcode: null,
        price: 3.2,
        quantityInStock: 12,
        minStockAlert: 20,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      isNew: true,
    );

    await _inventoryService.addStockMovement(
      companyId: tenantId,
      productId: aspirin.id,
      movementType: 'entry',
      quantity: 50,
    );
  }

  void _clearCollections() {
    _products.clear();
    _categories.clear();
    _movements.clear();
  }

  @override
  void dispose() {
    _clearRealtimeResources();
    super.dispose();
  }
}
