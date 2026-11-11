import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/access_providers.dart';
import 'bandeau_hors_ligne.dart';
import 'ecriture.dart';
import 'etats.dart';

/// Cadre d'un éditeur plein écran, hors de la coquille : ✕ « Fermer », titre,
/// « Enregistrer » (ou [libelleAction]), bandeau hors ligne. Quitter avec des
/// changements (✕, retour Android) demande « Abandonner les modifications ? ».
class EditeurPleinEcran extends ConsumerWidget {
  const EditeurPleinEcran({
    super.key,
    required this.titre,
    required this.closePath,
    required this.body,
    this.dirty = false,
    this.saving = false,
    this.onSave,
    this.abandonMessage = '',
    this.bottomBar,
    this.libelleAction = 'Enregistrer',
    this.libelleEnCours = 'Enregistrement',
    this.fermerParRetour = false,
  });

  final String titre;

  /// Page ouverte en quittant l'éditeur.
  final String closePath;
  final Widget body;

  /// Des changements ne sont pas enregistrés.
  final bool dirty;

  /// Un enregistrement est en cours : le bouton attend.
  final bool saving;

  /// `null` : pas de bouton « Enregistrer » (chargement, lecture seule).
  final VoidCallback? onSave;

  /// Texte de la confirmation d'abandon.
  final String abandonMessage;

  /// Barre fixée en bas (calculs de la recette).
  final Widget? bottomBar;

  /// Libellé du bouton d'action (« Envoyer ») et pendant l'action (« Envoi »).
  final String libelleAction;
  final String libelleEnCours;

  /// Vrai pour un écran ouvert par `push` : quitter revient à l'écran
  /// précédent, et à [closePath] seulement s'il n'y en a pas (adresse ouverte
  /// directement).
  final bool fermerParRetour;

  Future<void> _leave(BuildContext context) async {
    // ticket: aucun (confirmation)
    if (dirty && !await confirmerAbandon(context, abandonMessage)) return;
    if (!context.mounted) return;
    if (fermerParRetour && context.canPop()) {
      context.pop();
    } else {
      context.go(closePath);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final save = onSave;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave(context));
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Fermer',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => _leave(context),
            icon: const Icon(Icons.close),
          ),
          title: Text(titre),
          actions: [
            if (save != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: saving ? null : save,
                  child: saving
                      ? IndicateurBouton(label: libelleEnCours)
                      : Text(libelleAction),
                ),
              ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (offline) const BandeauHorsLigne(),
            Expanded(child: body),
          ],
        ),
        bottomNavigationBar: bottomBar,
      ),
    );
  }
}

/// Fait défiler l'éditeur jusqu'au champ de [context] (premier champ en erreur).
Future<void> montrerChamp(BuildContext? context) async {
  if (context == null || !context.mounted) return;
  await Scrollable.ensureVisible(
    context,
    duration: const Duration(milliseconds: 250),
    alignment: 0.1,
  );
}
