import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../models/stock_movement_model.dart';

class ProductRepository {
  final SupabaseClient _supabase;

  ProductRepository(this._supabase);

  Future<List<Product>> getProducts() async {
    final response = await _supabase
        .from('products')
        .select()
        .order('created_at', ascending: false);

    return (response as List).map((json) => Product.fromJson(json)).toList();
  }

  Future<List<Product>> getLowStockProducts() async {
    final response = await _supabase.from('products').select();
    final allProducts = (response as List)
        .map((json) => Product.fromJson(json))
        .toList();
    return allProducts
        .where((p) => p.quantityInStock <= p.minStockAlert)
        .toList();
  }

  Future<Product> addProduct(Product product) async {
    final response = await _supabase
        .from('products')
        .insert(product.toJson())
        .select()
        .single();

    return Product.fromJson(response);
  }

  Future<void> updateProduct(Product product) async {
    await _supabase
        .from('products')
        .update(product.toJson())
        .eq('id', product.id);
  }

  Future<void> deleteProduct(String id) async {
    await _supabase.from('products').delete().eq('id', id);
  }

  Future<void> recordStockMovement(StockMovement movement) async {
    await _supabase.from('stock_movements').insert(movement.toJson());

    final productResp = await _supabase
        .from('products')
        .select('quantity')
        .eq('id', movement.productId)
        .single();
    // Safely cast or get default 0
    final currentQuantity =
        int.tryParse(productResp['quantity']?.toString() ?? '0') ?? 0;

    int newQuantity = movement.movementType == 'entry'
        ? currentQuantity + movement.quantity
        : currentQuantity - movement.quantity;

    await _supabase
        .from('products')
        .update({'quantity': newQuantity})
        .eq('id', movement.productId);
  }
}
