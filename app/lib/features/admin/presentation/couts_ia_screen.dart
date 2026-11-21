import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/encadre.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../ai/data/ai_repository.dart';
import '../../ai/domain/comptes_ia.dart';
import '../../ai/domain/reglages_ia.dart';
import '../../ai/presentation/ai_providers.dart';
import '../../ai/presentation/ligne_ia_ce_mois.dart';
import '../../auth/presentation/access_providers.dart';
import '../../members/domain/member.dart';
import '../../members/presentation/members_providers.dart';
import '../../tickets/presentation/tickets_providers.dart';
import '../domain/postes_ia.dart';

/// Page d'usage de la Console Anthropic, qui fait foi pour la facture.
final kConsoleAnthropicUsage = Uri.https('console.anthropic.com', '/usage');

/// Admin › Coûts de l'IA (ADR-016, section 9) : comptes d'un mois par personne
/// et par poste, lus par `get()` (aucun écouteur, P60), montants tels que
/// stockés, jamais recalculés.
class CoutsIaScreen extends ConsumerStatefulWidget {
  const CoutsIaScreen({super.key});

  static const titre = 'Coûts de l\'IA';
  static const sousTitre =
      'Dépense de l\'IA par mois, par personne et par poste';
  static const chargement = 'Chargement des coûts';
  static const lectureImpossible = 'Impossible de lire les coûts de l\'IA.';
  static const horsLigneSansCache =
      'Hors ligne. Les coûts demandent le réseau.';
  static const horsLigne =
      'Hors ligne. Coûts lus sur cet appareil : ils peuvent ne pas être à '
      'jour.';
  static const tarifsEnPanne =
      'Tarifs en panne : les appels en cours partent sans montant.';
  static const ouvrirMoteur = 'Ouvrir Moteur d\'IA';
  static const nomsIndisponibles =
      'Noms indisponibles : les membres n\'ont pas pu être lus.';
  static const membreRetire = 'Membre retiré';
  static const nomNonRenseigne = 'Nom non renseigné';
  static const tronque = '50 premières personnes affichées.';
  static const noteFacture =
      'Les montants sont estimés avec la grille au moment de chaque appel. La '
      'facture fait foi dans la Console Anthropic.';
  static const ouvrirConsole = 'Ouvrir la Console Anthropic';
  static const posteInconnu = 'Poste inconnu';
  static const mois = 'Mois';

  static String vide(String mois) => 'Aucun appel à l\'IA en $mois.';

  static String sansMontant(int n) => n == 1
      ? '1 appel sans montant : tarifs en panne. Le total ne le compte pas.'
      : '$n appels sans montant : tarifs en panne. Le total ne les compte '
            'pas.';

  static String echecs(int n) => n == 1
      ? '1 appel en échec (délai dépassé ou serveur indisponible), compté dans '
            'les tours.'
      : '$n appels en échec (délai dépassé ou serveur indisponible), comptés '
            'dans les tours.';

  static String illisibles(int n) => n == 1
      ? '1 compte illisible n\'est pas affiché.'
      : '$n comptes illisibles ne sont pas affichés.';

  static String total(ComptesPoste t, int personnes) => [
    'Total : ${t.montantInconnu ? 'montant inconnu' : formatMontantUsd(t.montantUsd)}',
    formatTours(t.appels),
    personnes == 1 ? '1 personne' : '$personnes personnes',
  ].join(' · ');

  @override
  ConsumerState<CoutsIaScreen> createState() => _CoutsIaScreenState();
}

/// « Novembre 2026 ».
String libelleMois(int annee, int mois) {
  final t = formatMoisAnnee(annee, mois);
  return '${t[0].toUpperCase()}${t.substring(1)}';
}

/// Montant d'une ligne : « ≈ 0,42 $ » ou « montant inconnu ».
String montantLigne(ComptesPoste c) =>
    c.montantInconnu ? 'montant inconnu' : formatMontantUsd(c.montantUsd);

class _CoutsIaScreenState extends ConsumerState<CoutsIaScreen> {
  /// Nombre de mois avant le mois en cours ; 0 : le mois en cours.
  int _recul = 0;

  /// Personnes dépliées, par identifiant de document.
  final _ouvertes = <String>{};

  Future<void> _ouvrirConsole() async {
    final messenger = ScaffoldMessenger.of(context);
    final errors = ref.read(errorReportServiceProvider);
    Object? error;
    StackTrace? stackTrace;
    var ok = false;
    try {
      ok = await ref.read(ouvrirLienProvider)(kConsoleAnthropicUsage);
    } catch (e, st) {
      error = e;
      stackTrace = st;
    }
    if (ok) return;
    errors.reportError(
      feature: 'admin.ai_costs_console',
      error: error ?? StateError('ouverture refusée par le système'),
      stackTrace: stackTrace ?? StackTrace.current,
      context: 'page d\'usage de la Console Anthropic',
    );
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Impossible d\'ouvrir le lien.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(horlogeProvider)();
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final choisi = moisAvant(now, _recul);
    final cle =
        '${choisi.annee.toString().padLeft(4, '0')}-'
        '${choisi.mois.toString().padLeft(2, '0')}';
    final comptesAsync = ref.watch(comptesDuMoisProvider(cle));
    final membresAsync = ref.watch(membersListProvider);
    final grille = ref.watch(grilleIaProvider);
    final theme = Theme.of(context);

    final menuMois = DropdownButtonFormField<int>(
      key: ValueKey('mois-$_recul'),
      initialValue: _recul,
      isExpanded: true,
      decoration: const InputDecoration(labelText: CoutsIaScreen.mois),
      items: [
        for (var i = 0; i <= 12; i++)
          DropdownMenuItem(
            value: i,
            child: Text(() {
              final m = moisAvant(now, i);
              final l = libelleMois(m.annee, m.mois);
              return i == 0 ? '$l (en cours)' : l;
            }()),
          ),
      ],
      onChanged: (v) => setState(() {
        _recul = v ?? 0;
        _ouvertes.clear();
      }),
    );

    final grilleEnPanne = switch (grille.value?.document) {
      DocumentAbsent() || DocumentIllisibleTrouve() => true,
      _ => false,
    };

    final List<Widget> corps;
    final lu = comptesAsync.value;
    if (lu == null) {
      corps = comptesAsync.hasError
          ? [
              EtatErreur(
                message: offline
                    ? CoutsIaScreen.horsLigneSansCache
                    : CoutsIaScreen.lectureImpossible,
                onRetry: () => ref.invalidate(comptesDuMoisProvider(cle)),
              ),
            ]
          : [const EtatChargement(label: CoutsIaScreen.chargement)];
    } else {
      corps = _comptes(
        context,
        lu,
        membresAsync,
        moisTexte: formatMoisAnnee(choisi.annee, choisi.mois),
        offline: offline,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        menuMois,
        const SizedBox(height: 16),
        if (grilleEnPanne) ...[
          Encadre(
            ton: TonEncadre.erreur,
            icone: Icons.error_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(CoutsIaScreen.tarifsEnPanne),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => context.go(AppRoutes.adminAiEngine),
                  child: const Text(CoutsIaScreen.ouvrirMoteur),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        ...corps,
        const SizedBox(height: 24),
        Text(
          CoutsIaScreen.noteFacture,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => unawaited(_ouvrirConsole()),
            icon: const Icon(Icons.open_in_new),
            label: const Text(CoutsIaScreen.ouvrirConsole),
          ),
        ),
      ],
    );
  }

  List<Widget> _comptes(
    BuildContext context,
    ComptesDuMois lu,
    AsyncValue<List<Member>> membresAsync, {
    required String moisTexte,
    required bool offline,
  }) {
    final theme = Theme.of(context);
    final comptes =
        [
          for (final c in lu.comptes)
            if (c is DocumentValide<CompteMoisIa> && c.value.total.appels > 0)
              c.value,
        ]..sort((a, b) {
          final m = b.total.montantUsd.compareTo(a.total.montantUsd);
          return m != 0 ? m : b.total.appels.compareTo(a.total.appels);
        });
    final illisibles = lu.comptes.whereType<DocumentInvalide<CompteMoisIa>>();
    final membres = membresAsync.value;
    final parEmail = {for (final m in membres ?? <Member>[]) m.email: m};
    final total = comptes.fold(ComptesPoste.vide, (a, c) => a + c.total);
    final petit = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    String nom(CompteMoisIa c) {
      final email = c.email;
      if (membres == null || email == null) return email ?? c.uid;
      final m = parEmail[email];
      if (m == null) return CoutsIaScreen.membreRetire;
      return m.displayName ?? CoutsIaScreen.nomNonRenseigne;
    }

    final large = MediaQuery.sizeOf(context).width >= kExpandedMinWidth;
    String resumeLigne(CompteMoisIa c) => [
      formatTours(c.total.appels),
      montantLigne(c.total),
      if (c.total.sansMontant > 0) '${c.total.sansMontant} sans montant',
    ].join(' · ');

    bool emailAffiche(CompteMoisIa c) {
      if (membres == null || c.email == null) return false;
      final m = parEmail[c.email];
      return m == null || m.displayName == null;
    }

    return [
      if (lu.fromCache && offline) ...[
        const Encadre(
          ton: TonEncadre.avertissement,
          icone: Icons.cloud_off_outlined,
          child: Text(CoutsIaScreen.horsLigne),
        ),
        const SizedBox(height: 16),
      ],
      if (comptes.isEmpty)
        Text(CoutsIaScreen.vide(moisTexte), style: theme.textTheme.bodyLarge)
      else ...[
        Semantics(
          header: true,
          child: Text(
            CoutsIaScreen.total(total, comptes.length),
            style: theme.textTheme.titleMedium,
          ),
        ),
        if (total.sansMontant > 0) ...[
          const SizedBox(height: 8),
          Encadre(
            ton: TonEncadre.avertissement,
            icone: Icons.warning_amber_outlined,
            child: Text(CoutsIaScreen.sansMontant(total.sansMontant)),
          ),
        ],
        if (total.echecs > 0) ...[
          const SizedBox(height: 8),
          Text(CoutsIaScreen.echecs(total.echecs), style: petit),
        ],
        if (membresAsync.hasError && membres == null) ...[
          const SizedBox(height: 8),
          Text(CoutsIaScreen.nomsIndisponibles, style: petit),
        ],
        const SizedBox(height: 8),
        for (final c in comptes)
          ExpansionTile(
            key: ValueKey('cout-${c.id}'),
            initiallyExpanded: _ouvertes.contains(c.id),
            onExpansionChanged: (o) =>
                o ? _ouvertes.add(c.id) : _ouvertes.remove(c.id),
            tilePadding: EdgeInsets.zero,
            // À 840 px et plus, tours et montant à droite du nom, sur une
            // ligne ; dessous au téléphone.
            title: large
                ? Row(
                    children: [
                      Expanded(child: Text(nom(c))),
                      const SizedBox(width: 16),
                      Text(resumeLigne(c)),
                    ],
                  )
                : Text(nom(c)),
            subtitle: switch ((large, emailAffiche(c))) {
              (true, false) => null,
              (true, true) => Text(c.email!),
              (false, false) => Text(resumeLigne(c)),
              (false, true) => Text('${c.email}\n${resumeLigne(c)}'),
            },
            children: [
              for (final e in c.postes.entries)
                if (e.value.appels > 0) _DetailPoste(cle: e.key, c: e.value),
            ],
          ),
        if (lu.tronque) ...[
          const SizedBox(height: 8),
          Text(CoutsIaScreen.tronque, style: petit),
        ],
      ],
      if (illisibles.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(CoutsIaScreen.illisibles(illisibles.length), style: petit),
      ],
    ];
  }
}

/// Détail d'un poste pour une personne.
class _DetailPoste extends StatelessWidget {
  const _DetailPoste({required this.cle, required this.c});

  final String cle;
  final ComptesPoste c;

  String _n(int v) => formatNombre(v.toDouble(), decimales: 0);

  @override
  Widget build(BuildContext context) {
    final poste = posteIa(cle);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TitreSection(
            poste?.libelle ?? cle,
            niveau: NiveauTitre.sousSection,
            trailing: poste == null ? CoutsIaScreen.posteInconnu : null,
          ),
          LigneFiche(
            label: 'Tours',
            value:
                '${_n(c.appels)} · Échecs ${_n(c.echecs)} · Sans montant '
                '${_n(c.sansMontant)}',
          ),
          if (MediaQuery.sizeOf(context).width >= kExpandedMinWidth)
            // Jetons sur deux colonnes à 840 px et plus.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LigneFiche(
                        label: 'Jetons d\'entrée',
                        value: _n(c.jetonsEntree),
                      ),
                      LigneFiche(
                        label: 'Cache écrit',
                        value: _n(c.jetonsCacheEcrits),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LigneFiche(
                        label: 'Cache lu',
                        value: _n(c.jetonsCacheLus),
                      ),
                      LigneFiche(
                        label: 'Jetons de sortie',
                        value: _n(c.jetonsSortie),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            LigneFiche(
              label: 'Jetons',
              value:
                  'entrée ${_n(c.jetonsEntree)}, cache écrit '
                  '${_n(c.jetonsCacheEcrits)}, cache lu ${_n(c.jetonsCacheLus)}, '
                  'sortie ${_n(c.jetonsSortie)}',
            ),
          LigneFiche(label: 'Montant', value: montantLigne(c)),
        ],
      ),
    );
  }
}

/// Alertes de Moteur d'IA pour la pastille de l'accueil Admin : grille
/// absente ou illisible, poste sans réglage lisible. « Tarifs à revérifier »
/// ne compte pas.
int alertesMoteurIa({
  required LectureIa<GrilleTarifaire>? grille,
  required LectureIa<PolitiqueIa>? politique,
}) {
  if (grille == null || politique == null) return 0;
  var n = switch (grille.document) {
    DocumentAbsent() || DocumentIllisibleTrouve() => 1,
    _ => 0,
  };
  final doc = politique.document;
  for (final p in kPostesIa) {
    final lisible =
        doc is DocumentTrouve<PolitiqueIa> && doc.value.reglage(p.cle) != null;
    final absentDuCache = doc is DocumentAbsentDuCache<PolitiqueIa>;
    if (!lisible && !absentDuCache) n++;
  }
  return n;
}
