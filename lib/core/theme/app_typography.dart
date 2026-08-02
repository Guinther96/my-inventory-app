import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Styles de texte nommes, au-dessus d'Inter (deja configure globalement
/// via GoogleFonts.interTextTheme dans AppTheme). A utiliser pour les
/// titres/labels qui ont un role precis dans la hierarchie visuelle, plutot
/// que de repartir d'un TextStyle() ad hoc a chaque ecran.
///
/// Chaque methode prend le [BuildContext] pour resoudre sa couleur par
/// defaut via Theme.of(context).colorScheme (adapte clair/sombre) plutot
/// qu'une constante AppColors figee en mode clair. [color] reste disponible
/// pour un override explicite.
class AppTypography {
  AppTypography._();

  static TextStyle pageTitle(BuildContext context, {Color? color}) =>
      GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      );

  static TextStyle sectionTitle(BuildContext context, {Color? color}) =>
      GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      );

  static TextStyle cardTitle(BuildContext context, {Color? color}) =>
      GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      );

  static TextStyle body(BuildContext context, {Color? color}) =>
      GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      );

  static TextStyle bodyMedium(BuildContext context, {Color? color}) =>
      GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      );

  static TextStyle small(BuildContext context, {Color? color}) =>
      GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      );
}
