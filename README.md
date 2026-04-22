# BiznisPlus - Documentation de l'application

BiznisPlus est une application Flutter de gestion de stock en francais.
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

Si vous testez les emails Supabase (confirmation et mot de passe oublie), passez les URLs de redirection publiques:

```bash
flutter run -d chrome --web-port=8080 \
	--dart-define=EMAIL_CONFIRM_REDIRECT_URL=https://votre-domaine/confirm-email?confirmed=1 \
	--dart-define=PASSWORD_RESET_REDIRECT_URL=https://votre-domaine/change-password?recovery=1
```

Important: ces deux URLs doivent etre ajoutees dans Supabase > Auth > URL Configuration > Redirect URLs.

## Analyse statique

```bash
flutter analyze
```

## Deploiement Netlify

Le projet est configure pour un deploiement Netlify via connexion GitHub.

- Fichier de configuration: `netlify.toml`
- Dossier publie par Netlify: `build/web`
- Regle SPA: toutes les routes sont redirigees vers `index.html`

Si vous connectez le depot a Netlify:

1. Ouvrez les parametres du site Netlify.
2. Verifiez que le dossier de publication est `build/web`.
3. Verifiez que la commande de build vient bien du fichier `netlify.toml`.
4. Lancez un nouveau deploy apres la connexion ou apres un push GitHub.

Important:

- Le dossier `build/` n'est pas versionne dans Git, donc il ne faut pas compter sur `build/web/_redirects` dans un deploy GitHub.
- La regle de redirection doit exister dans le depot, ici via `web/_redirects` et `netlify.toml`.

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
