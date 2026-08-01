import 'package:flutter/material.dart';

/// Palette de marque BiznisPlus. Source de verite unique pour toute
/// couleur "en dur" ailleurs dans l'app: preferez toujours ces constantes
/// (ou colorScheme derive dans AppTheme) a un Color(0xFF...) local.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryHover = Color(0xFF1D4ED8);

  static const Color background = Color(0xFFF8FAFC);
  static const Color card = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);

  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  // Variante sombre: mêmes rôles sémantiques, valeurs adaptées pour rester
  // lisibles sur fond sombre sans dénaturer l'identité de marque.
  static const Color backgroundDark = Color(0xFF0F1720);
  static const Color cardDark = Color(0xFF17212C);
  static const Color borderDark = Color(0xFF2A3543);
  static const Color textPrimaryDark = Color(0xFFF1F5F9);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
}
