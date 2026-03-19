class AppConstants {
  static const String appName = 'StockPro';

  static const String supabaseUrl = 'https://ylzkzcogrmzcnwviktya.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_FoRe55nJnCDrqJ7A3IBRWw_eN97kzbE';

  static bool get isSupabaseConfigured {
    final url = supabaseUrl.trim();
    final key = supabaseAnonKey.trim();

    return url.isNotEmpty && key.isNotEmpty;
  }
}
