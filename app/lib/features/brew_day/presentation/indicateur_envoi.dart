import 'package:flutter/material.dart';

import '../../../core/presentation/bandeau_hors_ligne.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';

/// Saisie refusée par le serveur (HS7), affichée jusqu'à la fermeture de l'écran.
class SaisieRefusee {
  const SaisieRefusee({required this.libelle, this.reprendre});

  /// « Densité 1057,9 à 12:10 ».
  final String libelle;

  /// « Saisir à nouveau », pour une mesure.
  final VoidCallback? reprendre;
}

/// État de l'envoi des saisies, dans la barre de l'écran du jour.
class IndicateurEnvoi extends StatelessWidget {
  const IndicateurEnvoi({
    super.key,
    required this.enAttente,
    required this.horsLigne,
    required this.refus,
    required this.detailAttente,
    required this.web,
  });

  final int enAttente;
  final bool horsLigne;
  final List<SaisieRefusee> refus;

  /// « 3 mesures, 2 étapes » ; vide quand rien n'attend.
  final String detailAttente;
  final bool web;

  /// « 3 saisies » ou « 1 saisie ».
  static String saisies(int n) => '$n saisie${n > 1 ? 's' : ''}';

  ({IconData icon, String texte, String message}) _etat() {
    if (refus.isNotEmpty) {
      return (
        icon: Icons.warning_amber,
        texte: '${refus.length} refusée${refus.length > 1 ? 's' : ''}',
        message:
            '${saisies(refus.length)} refusée${refus.length > 1 ? 's' : ''} par le '
            'serveur.',
      );
    }
    if (enAttente == 0) {
      return (
        icon: Icons.cloud_done_outlined,
        texte: 'Envoyé',
        message: 'Tout est envoyé.',
      );
    }
    if (horsLigne) {
      return (
        icon: Icons.cloud_off,
        texte: 'Hors ligne · $enAttente',
        message: 'Hors ligne, ${saisies(enAttente)} en attente du réseau.',
      );
    }
    return (
      icon: Icons.cloud_upload_outlined,
      texte: 'Envoi · $enAttente',
      message: '${saisies(enAttente)} en cours d\'envoi.',
    );
  }

  void _details(BuildContext context) {
    final detail = detailAttente;
    final etat = _etat();
    showFeuilleOuDialogue<void>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Envoi des saisies',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(horsLigne ? BandeauHorsLigne.message : etat.message),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('En attente du réseau : $detail.'),
            const SizedBox(height: 8),
            Text(
              web
                  ? 'Ne fermez pas cet onglet avant le retour du réseau.'
                  : 'Gardées sur ce téléphone, même si l\'application se ferme.',
            ),
          ],
          for (final r in refus)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Refusée par le serveur : ${r.libelle}. Elle n\'est pas '
                    'enregistrée.',
                  ),
                  if (r.reprendre != null)
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        r.reprendre!();
                      },
                      child: const Text('Saisir à nouveau'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final etat = _etat();
    final isRefus = refus.isNotEmpty;
    final fond = isRefus ? scheme.errorContainer : scheme.secondaryContainer;
    final texte = isRefus
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;
    return Semantics(
      button: true,
      liveRegion: true,
      label: etat.message,
      onTap: () => _details(context),
      excludeSemantics: true,
      child: Material(
        color: fond,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _details(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(etat.icon, size: 20, color: texte),
                  const SizedBox(width: 6),
                  // Borné : à 200 %, le titre et l'heure restent visibles.
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.34,
                    child: Text(etat.texte, style: TextStyle(color: texte)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
