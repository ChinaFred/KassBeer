# Changelog

Une entrée par version, la plus récente en tête, sous la date du jour. Titre
`### vX.Y.Z — fonctionnel` (ce que voit l'utilisateur) ou `— technique` (architecture,
données, outillage), ou les deux.

## 2026-11-07

### v0.1.0 — technique

Démarrage du projet. Pile retenue (ADR-001) : Flutter pour Android et le web, Firebase
(Auth Google, Firestore `europe-west1`, Hosting, App Distribution), sans serveur ni IA en
version 1. Les calculs de brassage vivront dans le paquet Dart pur `brewing/`. `CLAUDE.md`
reçoit les sections du projet, les règles du jour de brassage hors ligne, des unités, des
prix privés et du cache web, et dix contrôles (P1 à P10). Outillage : formateurs Dart et
Prettier, version portée par `app/pubspec.yaml`, installation de Flutter 3.44.6 en session
cloud. Le bac à sable et son skill sont retirés : le projet est petit et le délai court.

