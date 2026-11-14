import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/access_providers.dart';
import 'bandeau_hors_ligne.dart';
import 'ecriture.dart';
import 'etats.dart';
import 'menu_compte.dart';
import 'zone_capture.dart';

/// Largeur de la barre du haut hors bouton d'action : ✕ (56), marge du bouton
/// (8), menu du compte (48) et sa marge (8).
const double _largeurHorsAction = 56 + 8 + 48 + 8;

/// Cadre d'un éditeur plein écran, hors de la coquille : ✕ « Fermer », titre,
/// « Enregistrer » (ou [libelleAction]), menu du compte, bandeau hors ligne.
/// Quitter avec des changements (✕, retour Android, « Tickets à traiter »,
/// « Mes processus » ou « Se déconnecter » du menu du compte) demande
/// « Abandonner les modifications ? ».
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

  /// Vrai si rien n'est à perdre, ou si l'utilisateur abandonne.
  Future<bool> _peutQuitter(BuildContext context) async =>
      !dirty ||
      // ticket: aucun (confirmation)
      await confirmerAbandon(context, abandonMessage);

  Future<void> _leave(BuildContext context) async {
    if (!await _peutQuitter(context)) return;
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
                // Borné par la place que laissent ✕ et le menu du compte : à
                // 360 dp et texte à 200 %, le libellé se réduit au lieu de
                // déborder.
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(
                      0,
                      MediaQuery.sizeOf(context).width - _largeurHorsAction,
                    ),
                  ),
                  child: FilledButton(
                    onPressed: saving ? null : save,
                    child: saving
                        ? IndicateurBouton(label: libelleEnCours)
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(libelleAction),
                          ),
                  ),
                ),
              ),
            // Quitter par le menu avec des changements : même confirmation
            // que ✕.
            MenuCompte(
              avantDeQuitter: dirty ? () => _peutQuitter(context) : null,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: ZoneCapture(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (offline) const BandeauHorsLigne(),
              Expanded(child: body),
            ],
          ),
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
