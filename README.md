# Lumaris — iOS app

Application iPhone native (SwiftUI) du workspace Lumaris : authentification,
tâches / événements / récurrentes, matières & chapitres, et emploi du temps
ÉcoleDirecte. Backend = les workers Cloudflare existants, aucun backend
propre à ce repo.

## Stack

- **SwiftUI** (iOS 17+) — `@Observable`/`ObservableObject`, async/await
- **Xcode 16+ synchronized groups** — tout fichier sous `src/` est compilé
  automatiquement, pas de liste de fichiers à maintenir
- **Keychain** pour la session (JWT + one-time token)
- **WKWebView** uniquement pour le widget Cloudflare Turnstile au login

## Arborescence

```
Lumaris.xcodeproj/        # projet Xcode (groupes synchronisés)
src/
  LumarisApp.swift        # @main, thème sombre + accent cyan
  Assets.xcassets/        # AppIcon, AccentColor
  Core/
    Config.swift          # URLs des workers par compte (<service>.<user>-cloudflare-account.workers.dev)
    AuthManager.swift     # login → JWT → exchange/renew (miroir de lib/auth.js)
    APIClient.swift       # authedFetch : Bearer JWT, retry silencieux sur 401
    WorkspaceStore.swift  # tables tasks + subjects/chapters + meta lookups
    JSON.swift            # accesseurs tolérants pour les lignes D1
    Keychain.swift
  Views/
    LoginView.swift       # identifiant + mot de passe + Turnstile (sheet WKWebView)
    RootView.swift        # Login ↔ TabView (Tâches / Matières / Emploi du temps)
    TasksView.swift       # filtres Toutes/Récurrentes/Événements/Corbeille, swipe actions
    TaskDetailView.swift  # détail + éditeur natif (toutes colonnes D1 utiles)
    SubjectsView.swift    # matières → chapitres → détail/édition
    TimetableView.swift   # grille ED 2 semaines + modale QCM 2FA
```

## Authentification

1. `POST authentication-client-worker.<user>-cloudflare-account.workers.dev/api/login`
   `{username, password, turnstileToken}` → `{jwt, oneTimeToken}`.
   Le worker ne répond jamais en cas d'échec → timeout 15 s → message générique.
2. `POST main-client-worker.<user>-cloudflare-account.workers.dev/api/auth/exchange`
   `{username, oneTimeToken}` → JWT frais (30 min) + one-time token rotatif.
3. Toutes les routes `/api/*` exigent `Authorization: Bearer <jwt>` ; sur 401
   l'app renouvelle silencieusement via l'exchange puis retente une fois.

L'identifiant de compte est saisi à la connexion (comme `/account/<user>/` sur
le web) et détermine le sous-domaine `*.workers.dev` de tous les workers.

## API consommées (main-client-worker)

| Route | Usage |
|---|---|
| `POST /api/tasks/list` | les 6 tables (tasks/repeat/events/trash) |
| `POST /api/tasks/create|update|toggle|delete|restore|meta` | CRUD + lookups |
| `POST /api/subjects/list|create-subject|update-subject|delete-subject|create-chapter|update-chapter|delete-chapter` | matières & chapitres |
| `GET /api/ed/timetable` (header `filter: true`) | emploi du temps 2 semaines |
| `POST /api/ed/qcm {choice}` | réponse au questionnaire 2FA ED |

Le flux QCM : si ED répond `{qcm_required, question, propositions}`, l'app
affiche la modale, poste le choix, puis recharge le timetable — comme le web.

## Build & install

```bash
open Lumaris.xcodeproj          # ou xcodebuild -scheme Lumaris -destination 'platform=iOS Simulator' build
```

- Bundle ID : `com.lumaris.app` — Deployment target iOS 17
- Signing : `CODE_SIGN_STYLE = Automatic` ; renseigner la team dans Xcode
  (Signing & Capabilities) pour installer sur device / TestFlight.

## Non encore porté (roadmap)

Sections hors scope initial : Intelligence (chat IA), Fichiers (MEGA),
Outils, Réglages, run des activités/tests, planificateur d'examen, import
de leçons, modèles, corbeille avancée (purge), notifications push.
