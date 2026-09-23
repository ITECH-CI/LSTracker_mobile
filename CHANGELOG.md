# Changelog — LSTracker Mobile

## 2.2.3 (build 9) — 2026-09-22

### Accès au détail depuis les tableaux de bord

- **Tableau de bord laboratoire** : les quatre cartes de la section « Suivi »
  (En transit, Résultats prêts, Résultats récupérés, Résultats déposés) donnent
  désormais accès au détail des échantillons. Elles n'étaient pas cliquables :
  le biologiste voyait un compteur sans pouvoir l'explorer.
- **Tableau de bord convoyeur** : les cartes « Déposés (à recevoir) » et
  « Reçus (à finaliser) » deviennent également navigables.
- Les trois tableaux de bord (administrateur, convoyeur, laboratoire) exposent
  maintenant le même niveau de détail. Une carte dont le compteur est à zéro
  reste non cliquable.

### Saisie d'un échantillon

- Libellés clarifiés : « Axe / Circuit (collecte) », avec la précision qu'il
  détermine les sites de collecte proposés, et mention « Indépendant du circuit
  de collecte » sous le laboratoire de destination. Les deux champs étaient
  déjà indépendants ; seul l'affichage prêtait à confusion.

## 2.2.2 (build 8) — 2026-05-29

### Synchronisation OpenELIS

- **Retrait de la saisie « Début analyse »** sur l'écran « résultat prêt » : la date de début d'analyse n'est plus saisie manuellement (champ, état et payload `analysis_started_date` supprimés). Elle est désormais dérivée d'OpenELIS via l'intégration oedatarepo côté serveur. Le modèle/DAO local conserve le champ pour un usage futur.

## 2.2.1 (build 7) — 2026-05-25

- Alignement de version avec le backend (release 2.2.1). Pas de changement fonctionnel mobile.

## 2.2.0 (build 6) — 2026-05-25

### Sécurité & confidentialité

- **Purge des données locales à la déconnexion** : la BD locale (samples + métadonnées) est désormais vidée à chaque logout. Auparavant seuls les tokens étaient effacés, ce qui exposait les données d'un compte à un autre utilisateur se connectant sur le même appareil.
- **Dialog adaptatif si modifications non synchronisées** : si des samples `dirty=1` sont en attente d'envoi au moment du logout, l'utilisateur a le choix entre « Synchroniser d'abord », « Forcer la déconnexion (perte de données) » ou « Annuler ».
- **Purge au login si changement d'utilisateur** : si le `userId` du nouvel utilisateur diffère du dernier connecté, la BD est purgée avant la nouvelle session. Si c'est le même utilisateur (re-login après expiration de session), la BD et les samples `dirty` sont préservés.

### Validation des dates aberrantes

- **Borne basse** : année en cours - 1. Toute date antérieure est rejetée à la saisie (ex. plus de samples avec « collection_date = 0204 »).
- **Borne haute** : aujourd'hui. Plus de saisies dans le futur.
- **`sample_edit_screen` durci** : les deux champs date qui étaient totalement libres (texte) sont passés en mode picker en lecture seule, avec validateur centralisé.
- Nouvelle classe `CustomDateUtils.validateCollectionDate` réutilisable.

### Dashboards mobile — cohérence

- **Fix double-comptage des échecs d'analyse** : le compteur `resultReady` incluait `ANALYSIS_FAILED`, qui était aussi exposé séparément en `analysisFailed`. Les badges qui agrégaient les deux double-comptaient. Désormais `resultReady = ANALYSIS_DONE` strictement.
- **Labels harmonisés** sur les dashboards convoyeur et utilisateur : « Déposés au labo » → « Déposés (à recevoir) », « Reçus au labo » → « Reçus (à finaliser) ». Aligne le vocabulaire sur les dashboards admin/labo et clarifie qu'il s'agit d'un statut courant, pas d'un événement de période.
- **Nouveau bandeau « Vue temps réel »** affiché en tête de chaque dashboard pour clarifier que les compteurs reflètent l'état actuel des échantillons, et peuvent différer des chiffres du tableau de bord web qui couvrent une période. Dismissible par session (réapparaît à la prochaine connexion).

### Notes techniques

- Le bouton logout du `AccountMenuButton` appelle désormais `AuthService.logout()` au lieu d'un nettoyage partiel improvisé.
- Le service `DashboardInfoNote.resetForNewSession()` est appelé automatiquement par `AuthService.login()` et `logout()`.
