import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category_model.dart';

class CategoryRepository {
  final SupabaseClient _supabase;

  CategoryRepository(this._supabase);

  Future<List<Category>> getCategories() async {
    final response = await _supabase
        .from('categories')
        .select()
        .order('name', ascending: true);

    return (response as List).map((json) => Category.fromJson(json)).toList();
  }

  Future<Category> addCategory(Category category) async {
    final response = await _supabase
        .from('categories')
        .insert(category.toJson())
        .select()
        .single();

    return Category.fromJson(response);
  }

  Future<void> updateCategory(Category category) async {
    await _supabase
        .from('categories')
        .update(category.toJson())
        .eq('id', category.id);
  }

  Future<void> deleteCategory(String id) async {
    await _supabase.from('categories').delete().eq('id', id);
  }
}
