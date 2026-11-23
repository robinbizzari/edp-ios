# EDP et Tri pour iPhone (AltStore)

Ce projet fabrique **deux applis** : **EDP** (école) et **Tri** (ménage de la galerie).

## EDP

L'appli EDP : ton site EDP en plein écran, plus ce qu'un site ne peut pas faire.

- **Connexion à l'ENT par ÉduConnect** : la vraie page s'ouvre sur le téléphone, comme dans l'appli Skolengo. Les devoirs du cahier de textes arrivent dans EDP.
- **Bus du matin et météo** : l'appli regarde dans quelle ville tu es. Ta position reste sur l'iPhone, elle n'est envoyée à personne.
- **Rappels** : 10 minutes avant chaque cours (avec la salle), devoirs la veille à 19 h, habits la veille à 21 h.
- **Tirer pour actualiser**, mode sombre synchronisé, scanner QR Pronote.

## Tri

- **Analyse toute ta photothèque** directement, sans sélecteur ni limite : doublons, photos similaires, floues, sombres, captures d'écran.
- **Tri au swipe**, mois par mois, comme sur le site.
- **Suppression pour de vrai dans Photos** en un geste (une seule confirmation d'iOS), avec 30 jours pour changer d'avis dans « Supprimés récemment ».
- Favoris synchronisés avec le cœur de Photos, **albums Tri créés dans Photos**, partage des originaux, lecture des vidéos.
- Tout se passe sur l'iPhone : aucune photo n'est envoyée sur Internet, et l'appli marche même hors connexion.

Au premier lancement, touche « Analyser toute ma galerie » et choisis **Accès complet** aux photos.

## Fabrication

Les applis sont fabriquées gratuitement par GitHub sur un Mac, sans signature. C'est AltStore qui la signe avec ton identifiant Apple au moment de l'installer.

## 1. Mettre le projet sur GitHub (une seule fois)

1. Va sur <https://github.com/new>.
2. Nom du dépôt : `edp-ios`. Choisis **Public** pour que les mises à jour apparaissent toutes seules dans AltStore (le dépôt ne contient que l'appli, pas ton serveur ni tes mots de passe). En **Privé**, tout marche aussi, mais tu devras installer chaque version à la main.
3. Ne coche rien d'autre, puis clique sur **Create repository**.
4. Sur la page suivante, clique sur **uploading an existing file**.
5. Ouvre le dossier `EDP-iOS` sur ton Bureau, sélectionne **tout son contenu** et glisse-le dans la page, puis clique sur **Commit changes** en bas.
6. Ajoute la « recette » de fabrication : en haut de la page du dépôt, **Add file** › **Create new file**. Dans le nom du fichier, tape exactement `.github/workflows/build.yml` (les « / » créent les dossiers). Ouvre `workflow-build.yml` (dans `EDP-iOS`) avec le Bloc-notes, copie tout, colle dans GitHub, puis **Commit changes**.

GitHub lance alors la fabrication des deux applis : onglet **Actions** de ton dépôt, compte environ 8 minutes. Quand le rond devient vert, la version est publiée dans **Releases** (colonne de droite de la page du dépôt).

## 2. Installer avec AltStore

**Avec la source (dépôt public, conseillé)**

1. Sur l'iPhone, ouvre AltStore › **Sources** › **+**.
2. Colle l'adresse : `https://github.com/TON-PSEUDO/edp-ios/releases/latest/download/apps.json`
3. Ouvre la source **Applis de Robin**, puis installe **EDP** et **Tri**.

Chaque nouvelle version apparaîtra ensuite dans l'onglet **Mises à jour** d'AltStore.

**À la main (marche aussi en privé)**

1. Sur l'iPhone, ouvre la page **Releases** du dépôt dans Safari (connecte-toi à GitHub si le dépôt est privé) et télécharge `EDP.ipa` et `Tri.ipa`.
2. Dans AltStore › **Mes apps** › **+**, choisis chaque fichier dans Téléchargements.

## 3. Premier lancement d'EDP

1. Connecte-toi à ton compte EDP (le même que sur le site).
2. Réglages › **Relier l'ENT** › ton lycée › **Se connecter sur la page de l'ENT** › **Élève** › ton académie › tes codes ÉduConnect.
3. Réglages › **Rappels** : active ceux que tu veux.

## Bon à savoir

- Avec un identifiant Apple gratuit, une appli installée par AltStore dure **7 jours**. AltStore la renouvelle tout seul quand ton PC (avec AltServer) et ton iPhone sont sur le même Wi-Fi.
- Un identifiant Apple gratuit permet **3 applis** installées par AltStore en même temps, AltStore compris : AltStore, EDP et Tri tiennent juste.
- Changer quelque chose dans le dépôt (par exemple l'adresse du serveur dans `project.yml`) refabrique automatiquement l'appli.
- Si la fabrication échoue : onglet **Actions**, ouvre l'exécution en rouge, et télécharge **journal-compilation** en bas de la page.
