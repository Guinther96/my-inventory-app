/// Echelle d'espacement unique de l'app: prefere ces constantes a des
/// valeurs magiques (EdgeInsets.all(17), SizedBox(height: 13)...) eparpillees
/// dans les widgets pour garder un rythme vertical/horizontal coherent.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}
