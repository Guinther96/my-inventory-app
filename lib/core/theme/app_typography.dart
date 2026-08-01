import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Styles de texte nommes, au-dessus d'Inter (deja configure globalement
/// via GoogleFonts.interTextTheme dans AppTheme). A utiliser pour les
/// titres/labels qui ont un role precis dans la hierarchie visuelle, plutot
/// que de repartir d'un TextStyle() ad hoc a chaque ecran.
class AppTypography {
  AppTypography._();

  static TextStyle pageTitle({Color? color}) => GoogleFonts.inter(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: color ?? AppColors.textPrimary,
  );

  static TextStyle sectionTitle({Color? color}) => GoogleFonts.inter(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: color ?? AppColors.textPrimary,
  );

  static TextStyle cardTitle({Color? color}) => GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: color ?? AppColors.textPrimary,
  );

  static TextStyle body({Color? color}) => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: color ?? AppColors.textPrimary,
  );

  static TextStyle bodyMedium({Color? color}) => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: color ?? AppColors.textPrimary,
  );

  static TextStyle small({Color? color}) => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: color ?? AppColors.textSecondary,
  );
}
