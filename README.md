# StockPro - Documentation de l'application

StockPro est une application Flutter de gestion de stock en francais.
Elle permet de gerer des produits et categories, enregistrer les mouvements de stock, consulter des indicateurs, et reinitialiser les donnees de demonstration.

## Fonctionnalites principales

- Tableau de bord dynamique:
- Nombre total de produits
- Produits en alerte de stock faible
- Valeur totale du stock
- Historique recent des mouvements
- Gestion des produits (CRUD):
- Ajouter, modifier, supprimer un produit
- Recherche par nom ou code-barres
- Gestion du prix, du stock courant, du seuil minimal, de la categorie
- Gestion des categories (CRUD):
- Ajouter, modifier, supprimer une categorie
- Detacher automatiquement la categorie des produits lies en cas de suppression
- Mouvements de stock:
- Entree, sortie, ajustement (valeur finale)
- Mise a jour automatique du stock du produit
- Historique recent des mouvements
- Rapports:
- Produits references
- Articles en stock
- Valeur totale du stock
- Nombre de mouvements enregistres
- Liste des produits en alerte
- Parametres:
- Reinitialisation complete des donnees vers un jeu de demonstration
- Interface responsive:
- `Drawer` sur mobile
- `Sidebar` sur desktop
- Application forcee en locale francaise (`fr_FR`)

## Architecture du projet

Le projet suit une structure par couches:

- `lib/core`: constantes, routing, theme
- `lib/data/models`: modeles `Product`, `Category`, `StockMovement`
- `lib/data/providers`: logique metier et etat global (`InventoryProvider`)
- `lib/presentation`: ecrans et widgets UI par fonctionnalite

### Gestion d'etat

- `provider` est utilise pour exposer l'etat global de l'inventaire.
- `InventoryProvider` centralise:
- CRUD produits/categories
- Calculs des KPI dashboard/rapports
- Enregistrement des mouvements de stock
- Persistance locale

### Persistance des donnees

- Stockage local via `shared_preferences`.
- Clefs utilisees:
- `inventory_products`
- `inventory_categories`
- `inventory_movements`
- Au premier lancement (si vide), des donnees de demonstration sont injectees.

## Ecrans et routes

Routes configurees dans `lib/core/routing/app_router.dart`:

- `/login` -> Ecran de connexion
- `/` -> Tableau de bord
- `/products` -> Produits
- `/categories` -> Categories
- `/movements` -> Mouvements de stock
- `/reports` -> Rapports
- `/settings` -> Parametres

## Stack technique

- Flutter (Dart)
- `provider`
- `go_router`
- `shared_preferences`
- `supabase_flutter` (initialisation conditionnelle selon les constantes)
- `flutter_localizations`

## Prerequis

- Flutter SDK installe
- Chrome installe (pour execution web)

## Installation

Depuis le dossier du projet (`my_inventory_app`):

```bash
flutter pub get
```

## Lancer l'application

Important: executez les commandes depuis le dossier racine du projet (celui qui contient `pubspec.yaml`).

```bash
flutter run -d chrome --web-port=8080
```

## Analyse statique

```bash
flutter analyze
```

## Notes importantes

- L'ecran de connexion est actuellement une UI simple sans authentification reelle.
- Supabase est initialise uniquement si `supabaseUrl` et `supabaseAnonKey` sont renseignes dans `lib/core/constants/app_constants.dart`.
- Les donnees sont locales au navigateur/appareil (via `shared_preferences`).

## Evolutions recommandees

- Authentification reelle (Supabase Auth)
- Synchronisation cloud (Supabase DB)
- Gestion des utilisateurs/roles
- Export PDF/CSV des rapports
- Tests unitaires et widget tests supplementaires
