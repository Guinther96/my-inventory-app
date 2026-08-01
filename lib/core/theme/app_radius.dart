import 'package:flutter/material.dart';

/// Echelle de rayons de bordure unique de l'app, pour remplacer les valeurs
/// 10/12/16/18/20/22/24/28 dispersees historiquement dans chaque ecran.
class AppRadius {
  AppRadius._();

  static const double sm = 10;
  static const double button = 14;
  static const double card = 20;
  static const double dialog = 24;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius buttonAll = BorderRadius.all(
    Radius.circular(button),
  );
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius dialogAll = BorderRadius.all(
    Radius.circular(dialog),
  );
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}
