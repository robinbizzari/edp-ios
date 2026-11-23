# Tri — cahier des charges (v2, novembre 2026)

Appli iPhone (AltStore) et site pour faire le ménage dans sa galerie, inspirée de Swipe Cleaner et de Papillon.
Tout se passe sur le téléphone : aucune photo ni aucun visage n'est envoyé.

## 1. Principes
- **Les photos d'abord** : grandes images, fond flou, peu de texte.
- **Gagner de la place vite** : on voit tout de suite combien on peut libérer et où.
- **Rien n'est supprimé sans validation** : corbeille, puis suppression groupée confirmée par iOS (30 jours
  dans « Supprimés récemment »).
- Couleurs d'origine (bleu iOS, rouge, vert, jaune favori), verre et dégradés doux.

## 2. Fonctions
| Fonction | Doit faire |
|---|---|
| Accueil | Carte héros (photos à trier, place à libérer), Personnes, mois en grandes cartes photo, nettoyage intelligent en tuiles, bibliothèque |
| Trier | Photo plein cadre, balayage (garder / jeter / favori / plus tard), tampons, annuler, albums |
| Nettoyage | Similaires, doublons exacts, floues, sombres, surexposées, captures, vidéos, **les plus lourdes** (photos et vidéos triées par taille) |
| Personnes | Visages regroupés, noms des contacts, « Est-ce aussi … ? », retirer une photo, albums dans Photos, réglage strict ↔ large |
| Corbeille | Taille totale, suppression en une fois (appli) ou guidée (web), restauration |

## 3. Qualité
- 0 erreur JavaScript, aucun débordement, cibles ≥ 44 px, mode sombre.
- Tests : appli simulée (photos, suppression, personnes) et version web.
- Le code iPhone compile sur GitHub Actions à chaque envoi.
