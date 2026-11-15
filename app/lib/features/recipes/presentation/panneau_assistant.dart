import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/corps_markdown.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/encadre.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../admin/domain/postes_ia.dart';
import '../../ai/data/ai_repository.dart';
import '../../ai/domain/comptes_ia.dart';
import '../../ai/domain/reglages_ia.dart';
import '../../ai/presentation/ai_providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/assistant_recette.dart';
import 'assistant_controleur.dart';

/// Libellés du panneau Assistant (proposition de `ux-designer` validée,
/// lot A1).
abstract final class TextesAssistant {
  static const titre = 'Assistant';
  static const ouvrir = 'Ouvrir l\'assistant';
  static const fermer = 'Fermer l\'assistant';
  static const avertissement =
      'Les chiffres viennent du calcul de Kass\'Beer ; une valeur marquée '
      '« proposée par l\'IA » est à vérifier.';
  static const mentionAnthropic =
      'La recette et vos messages partent chez Anthropic, qui les garde '
      '30 jours.';
  static const champ = 'Votre message';
  static const tropLongChamp = '1 500 caractères au plus.';
  static const envoyer = 'Envoyer';
  static const envoi = 'Envoi';
  static const analyser = 'Analyser la recette';
  static const ameliorer = 'Proposer des améliorations';
  static const vide =
      'Posez une question sur cette recette, ou choisissez un raccourci.';
  static const recetteVide =
      'Ajoutez au moins un malt ou un houblon pour une analyse utile.';
  static const horsLigne = 'L\'assistant demande le réseau.';
  static const redige = 'L\'assistant rédige sa réponse';
  static const resumeEnCours = 'L\'assistant résume la conversation';
  static const toursInconnus = 'Tours restants : inconnu';
  static const plusAucunTour = 'Plus aucun tour aujourd\'hui.';
  static const nouvelleConversation = 'Nouvelle conversation';
  static const copierConversation = 'Copier la conversation';
  static const copierReponse = 'Copier la réponse';
  static const reponseCopiee = 'Réponse copiée.';
  static const reponseNonCopiee = 'Impossible de copier la réponse.';
  static const conversationCopiee = 'Conversation copiée.';
  static const conversationNonCopiee = 'Impossible de copier la conversation.';
  static const vous = 'Vous';
  static const assistant = 'Assistant';
  static const titreResume = 'Résumé de la conversation précédente';
  static const resumer = 'Résumer et continuer';
  static const resumeCoute =
      'Le résumé coûte un tour. Il remplace l\'échange actuel et ouvre une '
      'nouvelle conversation.';
  static const tropLongue =
      'Cette conversation est trop longue pour continuer.';
  static const reponseRecue = 'Réponse de l\'assistant reçue';
  static const confirmerNouvelle = 'Commencer une nouvelle conversation ?';
  static const confirmerNouvelleTexte =
      'La conversation en cours sera effacée. Les tours déjà faits restent '
      'comptés aujourd\'hui.';
  static const effacer = 'Effacer et recommencer';
  static const ouvrirLien = 'Ouvrir ce lien ?';
  static const lienPropose = 'L\'assistant propose cette adresse :';
  static const lienNavigateur = 'Elle s\'ouvre dans votre navigateur.';

  static String toursRestants(int restants, int limite) =>
      'Tours restants aujourd\'hui : $restants sur $limite';

  static String reprise(DateTime d) =>
      'Reprise le ${formatJourCourt(d)} à ${formatHeure(d)}.';

  static String atteint(int n) => n == 1
      ? 'Cette conversation a atteint 1 tour.'
      : 'Cette conversation a atteint $n tours.';

  static String toursConversation(int restants, int limite) => restants == 1
      ? 'Cette conversation : 1 tour restant sur $limite'
      : 'Cette conversation : $restants tours restants sur $limite';

  /// Ce qui dépasse sa borne, nommé d'après `details.field`.
  static String tropLong(String? champ) {
    final quoi = switch (champ?.split('.').first) {
      'message' => 'votre message',
      'recipe' => 'la recette',
      'equipment' => 'l\'équipement',
      'style' => 'le style',
      'calculs' => 'les calculs',
      'aromas' => 'les arômes',
      'summary' => 'le résumé',
      'history' => 'la conversation',
      _ => 'la demande',
    };
    return 'Trop long pour l\'assistant : $quoi. Le tour n\'est pas compté.';
  }

  /// Message d'un échec, sans texte de la personne ni du modèle.
  static String echec(EchecAssistant e, {required bool admin}) =>
      switch (e.cause) {
        CauseEchecAssistant.reglagesAbsents =>
          'Assistant indisponible : les réglages de l\'IA manquent. '
              'L\'administrateur les enregistre dans Admin › Moteur d\'IA.',
        CauseEchecAssistant.posteFerme =>
          'L\'administrateur a fermé l\'assistant aux membres. Le tour '
              'n\'est pas compté.',
        CauseEchecAssistant.plafondJour => switch (e.quota) {
          (:final limite, :final DateTime repriseLe, restants: _) =>
            'Vous avez utilisé vos $limite tours d\'aujourd\'hui. '
                '${reprise(repriseLe)}',
          _ => 'Vous avez utilisé tous vos tours d\'aujourd\'hui.',
        },
        CauseEchecAssistant.conversationPleine => tropLongue,
        CauseEchecAssistant.tropLong => tropLong(e.champ),
        CauseEchecAssistant.creditEpuise =>
          admin
              ? 'Crédit de l\'IA épuisé pour ce mois. Le tour n\'est pas '
                    'compté. Rechargez le crédit dans la Console Anthropic.'
              : 'Crédit de l\'IA épuisé pour ce mois. Le tour n\'est pas '
                    'compté. Prévenez l\'administrateur.',
        CauseEchecAssistant.tropDemande =>
          'L\'IA est très demandée. Réessayez dans une minute. Le tour '
              'n\'est pas compté.',
        CauseEchecAssistant.reponseIllisible =>
          'L\'IA n\'a pas rendu de réponse lisible. Le tour est compté. '
              'Reformulez votre message.',
        CauseEchecAssistant.delaiDepasse =>
          'L\'assistant n\'a pas répondu à temps. Le tour est compté. '
              'Votre message est remis dans le champ.',
        CauseEchecAssistant.envoiImpossible =>
          'Envoi impossible. Le tour n\'est pas compté. Réessayez.',
        CauseEchecAssistant.reglageACorriger =>
          '${e.message ?? 'Réglage de l\'IA à corriger.'} Le tour n\'est pas '
              'compté.',
        CauseEchecAssistant.resultatInconnu =>
          'Résultat inconnu : ce tour a peut-être été compté. Votre message '
              'est remis dans le champ.',
        CauseEchecAssistant.refus =>
          'Demande refusée par le serveur. Le tour n\'est pas compté.',
        CauseEchecAssistant.recetteIllisible =>
          'La recette contient une valeur refusée. Corrigez-la avant '
              'd\'envoyer.',
      };
}

/// Panneau Assistant de l'éditeur de recette (ADR-015, section 8 ;
/// amendement « écrans du lot A1 ») : feuille du bas sous 840 px, colonne à
/// droite au-delà. La conversation vit dans [controleur], gardée tant que
/// l'éditeur est ouvert.
class PanneauAssistant extends ConsumerStatefulWidget {
  const PanneauAssistant({
    super.key,
    required this.controleur,
    required this.resumeCalculs,
    required this.recetteVide,
    required this.contexte,
    required this.onFermer,
    this.autofocus = false,
    this.titreEtFermer = true,
  });

  final ControleurAssistant controleur;

  /// Ligne de résumé des calculs (même texte que la barre des calculs).
  final String resumeCalculs;

  /// Recette sans malt ni houblon : l'état vide le signale, sans rien bloquer.
  final bool recetteVide;

  /// Données de la recette lues à l'envoi.
  final Future<ContexteAssistant?> Function() contexte;
  final VoidCallback onFermer;

  /// Curseur dans le champ à l'ouverture (colonne d'un grand écran).
  final bool autofocus;

  /// Titre « Assistant » et ✕ en tête ; faux sous le commutateur « Calculs /
  /// Assistant » (840 à 1 279 px), qui nomme déjà le panneau et le ferme :
  /// le menu ⋮ reste seul.
  final bool titreEtFermer;

  @override
  ConsumerState<PanneauAssistant> createState() => _PanneauAssistantState();
}

class _PanneauAssistantState extends ConsumerState<PanneauAssistant> {
  final _defilement = ScrollController();
  late int _reponses = widget.controleur.reponsesRecues;

  @override
  void initState() {
    super.initState();
    widget.controleur.addListener(_changement);
  }

  @override
  void didUpdateWidget(PanneauAssistant oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controleur != widget.controleur) {
      oldWidget.controleur.removeListener(_changement);
      widget.controleur.addListener(_changement);
    }
  }

  @override
  void dispose() {
    widget.controleur.removeListener(_changement);
    _defilement.dispose();
    super.dispose();
  }

  void _changement() {
    if (!mounted) return;
    final recues = widget.controleur.reponsesRecues;
    if (recues != _reponses) {
      _reponses = recues;
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          TextesAssistant.reponseRecue,
          TextDirection.ltr,
        ),
      );
    }
    // Dernier message visible après un envoi ou une réponse.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_defilement.hasClients) return;
      unawaited(
        _defilement.animateTo(
          _defilement.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  Future<void> _copier(
    String texte, {
    required String succes,
    required String echec,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final errors = ref.read(errorReportServiceProvider);
    var message = succes;
    try {
      await Clipboard.setData(ClipboardData(text: texte));
    } catch (error, stackTrace) {
      // Aucun texte de la conversation dans le rapport (P13).
      errors.reportError(
        feature: 'recipes.assistant_copy',
        error: error,
        stackTrace: stackTrace,
        context: 'longueur=${texte.length}',
      );
      message = echec;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _nouvelle() async {
    final c = widget.controleur;
    if (c.enCours) return;
    if (c.aDuContenu &&
        // ticket: aucun (confirmation)
        !await confirmerAction(
          context,
          titre: TextesAssistant.confirmerNouvelle,
          paragraphes: const [TextesAssistant.confirmerNouvelleTexte],
          libelle: TextesAssistant.effacer,
        )) {
      return;
    }
    c.nouvelleConversation();
  }

  /// Un lien montre son adresse complète avant de s'ouvrir (P59).
  Future<bool> _confirmerLien(BuildContext context, Uri uri) async {
    // ticket: aucun (confirmation)
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(TextesAssistant.ouvrirLien),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(TextesAssistant.lienPropose),
              const SizedBox(height: 8),
              SelectableText(uri.toString()),
              const SizedBox(height: 8),
              const Text(TextesAssistant.lienNavigateur),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ouvrir'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controleur;
    final access = ref.watch(grantedAccessProvider);
    final admin = access?.member.isAdmin ?? false;
    final fondateur = access?.member.founder ?? false;
    final offline = access?.offline ?? false;
    final politique = switch (ref.watch(politiqueIaProvider).value?.document) {
      DocumentTrouve(:final value) => value,
      _ => null,
    };
    final quotasAsync = ref.watch(quotasIaProvider);
    final now = ref.watch(horlogeProvider)();
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.champ]),
      builder: (context, _) {
        final reglage = politique?.reglage(kPosteAssistantRecette);
        final tours = _tours(
          c,
          politique: politique,
          quotas: quotasAsync.hasError ? null : quotasAsync.value,
          fondateur: fondateur,
          now: now,
        );
        return _contenu(
          context,
          c,
          admin: admin,
          offline: offline,
          tours: tours,
          limiteConversation: reglage?.toursParConversation,
          now: now,
        );
      },
    );
  }

  ToursRestants _tours(
    ControleurAssistant c, {
    required PolitiqueIa? politique,
    required LectureIa<QuotasIa>? quotas,
    required bool fondateur,
    required DateTime now,
  }) {
    final q = c.quota;
    if (q != null) {
      return ToursConnus(
        restants: q.restants,
        limite: q.limite,
        repriseLe: q.repriseLe,
      );
    }
    return toursRestants(
      politique: politique,
      quotas: quotas?.document,
      poste: kPosteAssistantRecette,
      fondateur: fondateur,
      now: now,
    );
  }

  Widget _contenu(
    BuildContext context,
    ControleurAssistant c, {
    required bool admin,
    required bool offline,
    required ToursRestants tours,
    required int? limiteConversation,
    required DateTime now,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final petit = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final echec = c.echec;
    final texte = c.champ.text;
    final tropLong = texte.length > kAssistantMessageMax;
    final journeeEpuisee =
        tours is ToursConnus &&
        tours.restants <= 0 &&
        (tours.repriseLe == null || now.isBefore(tours.repriseLe!));
    final limiteAtteinte =
        limiteConversation != null && c.toursFaits >= limiteConversation;
    final pleine =
        limiteAtteinte ||
        echec?.cause == CauseEchecAssistant.conversationPleine;
    final ferme = echec?.cause == CauseEchecAssistant.posteFerme;
    final peutEnvoyer =
        !offline &&
        !c.enCours &&
        texte.trim().isNotEmpty &&
        !tropLong &&
        !pleine &&
        !journeeEpuisee &&
        !ferme;

    final String ligneTours = switch (tours) {
      ToursInconnus() => TextesAssistant.toursInconnus,
      ToursConnus(:final restants, :final repriseLe) when restants <= 0 =>
        repriseLe == null
            ? TextesAssistant.plusAucunTour
            : '${TextesAssistant.plusAucunTour} '
                  '${TextesAssistant.reprise(repriseLe)}',
      ToursConnus(:final restants, :final limite) =>
        TextesAssistant.toursRestants(restants, limite),
    };
    final resteConversation = limiteConversation == null
        ? null
        : limiteConversation - c.toursFaits;

    final enTete = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: widget.titreEtFermer
                ? Semantics(
                    header: true,
                    child: Text(
                      TextesAssistant.titre,
                      style: theme.textTheme.titleMedium,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // ticket: /recettes/nouvelle/menu/assistant, /recettes/:id/modifier/menu/assistant
          PopupMenuButton<int>(
            tooltip: 'Plus d\'actions',
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 0,
                enabled: c.aDuContenu && !c.enCours,
                child: const Text(TextesAssistant.nouvelleConversation),
              ),
              PopupMenuItem(
                value: 1,
                enabled: c.aDuContenu,
                child: const Text(TextesAssistant.copierConversation),
              ),
            ],
            onSelected: (v) => v == 0
                ? unawaited(_nouvelle())
                : unawaited(
                    _copier(
                      c.texteCopie(),
                      succes: TextesAssistant.conversationCopiee,
                      echec: TextesAssistant.conversationNonCopiee,
                    ),
                  ),
          ),
          if (widget.titreEtFermer)
            IconButton(
              tooltip: TextesAssistant.fermer,
              onPressed: widget.onFermer,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );

    // [avant] et [apres] : ce qui défile avec la conversation en mode
    // compact (petite hauteur ou grand texte).
    Widget conversation({
      List<Widget> avant = const [],
      List<Widget> apres = const [],
    }) => LayoutBuilder(
      builder: (context, constraints) {
        final largeurBulle = constraints.maxWidth * 0.85;
        Widget bulle({
          required bool personne,
          required Widget child,
          String? lecture,
        }) => Align(
          alignment: personne
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: largeurBulle),
            child: Semantics(
              label: lecture,
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: personne
                      ? scheme.secondaryContainer
                      : scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: child,
              ),
            ),
          ),
        );
        Widget messagePersonne(String t) => bulle(
          personne: true,
          lecture: '${TextesAssistant.vous} :',
          child: Text(
            t,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSecondaryContainer,
            ),
          ),
        );
        Widget reponse(String t, {String? titre}) => bulle(
          personne: false,
          lecture: '${titre ?? TextesAssistant.assistant} :',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (titre != null) ...[
                Text(titre, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
              ],
              CorpsMarkdown(
                texte: t,
                avantOuverture: _confirmerLien,
                featureLien: 'recipes.assistant_link',
                contexteLien: 'lien d\'une réponse de l\'assistant',
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  tooltip: TextesAssistant.copierReponse,
                  onPressed: () => _copier(
                    t,
                    succes: TextesAssistant.reponseCopiee,
                    echec: TextesAssistant.reponseNonCopiee,
                  ),
                  icon: const Icon(Icons.copy_outlined),
                ),
              ),
            ],
          ),
        );
        final enAttente = c.enAttente;
        return ListView(
          controller: _defilement,
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
          children: [
            ...avant,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Encadre(
                      icone: Icons.info_outline,
                      child: Text(TextesAssistant.avertissement),
                    ),
                    if (c.resume case final r?)
                      reponse(r, titre: TextesAssistant.titreResume),
                    if (!c.aDuContenu && enAttente == null) ...[
                      const SizedBox(height: 16),
                      Text(
                        TextesAssistant.vide,
                        style: theme.textTheme.bodyLarge,
                      ),
                      if (widget.recetteVide) ...[
                        const SizedBox(height: 8),
                        Text(TextesAssistant.recetteVide, style: petit),
                      ],
                    ],
                    for (final m in c.messages)
                      m.auteur == AuteurMessage.personne
                          ? messagePersonne(m.texte)
                          : reponse(m.texte),
                    if (enAttente != null) messagePersonne(enAttente),
                    if (c.enCours)
                      bulle(
                        personne: false,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                c.appelEnCours == ModeAssistant.resume
                                    ? TextesAssistant.resumeEnCours
                                    : TextesAssistant.redige,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ...apres,
          ],
        );
      },
    );

    final bas = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (echec != null &&
              echec.cause != CauseEchecAssistant.conversationPleine) ...[
            Encadre(
              ton: TonEncadre.erreur,
              icone: Icons.error_outline,
              liveRegion: true,
              child: Text(TextesAssistant.echec(echec, admin: admin)),
            ),
            const SizedBox(height: 8),
          ],
          if (pleine) ...[
            Encadre(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    limiteAtteinte
                        ? TextesAssistant.atteint(limiteConversation)
                        : TextesAssistant.tropLongue,
                  ),
                  const SizedBox(height: 4),
                  const Text(TextesAssistant.resumeCoute),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed:
                            offline ||
                                c.enCours ||
                                journeeEpuisee ||
                                c.messages.isEmpty
                            ? null
                            : () => unawaited(c.resumer(widget.contexte)),
                        child: c.appelEnCours == ModeAssistant.resume
                            ? const IndicateurBouton(
                                label: TextesAssistant.envoi,
                              )
                            : const Text(TextesAssistant.resumer),
                      ),
                      OutlinedButton(
                        onPressed: c.enCours ? null : () => _nouvelle(),
                        child: const Text(TextesAssistant.nouvelleConversation),
                      ),
                    ],
                  ),
                  if (journeeEpuisee) ...[
                    const SizedBox(height: 4),
                    const Text(TextesAssistant.plusAucunTour),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (texte.isEmpty && !c.enCours && !pleine) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ActionChip(
                  label: const Text(TextesAssistant.analyser),
                  onPressed: () => c.champ.text = kRaccourciAnalyser,
                ),
                ActionChip(
                  label: const Text(TextesAssistant.ameliorer),
                  onPressed: () => c.champ.text = kRaccourciAmeliorer,
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: c.champ,
            enabled: !c.enCours,
            autofocus: widget.autofocus,
            minLines: 2,
            maxLines: 6,
            maxLength: kAssistantMessageMax,
            // Un collage trop long n'est pas coupé : le compteur passe en
            // erreur et « Envoyer » reste inactif.
            maxLengthEnforcement: MaxLengthEnforcement.none,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: TextesAssistant.champ,
              errorText: tropLong ? TextesAssistant.tropLongChamp : null,
            ),
          ),
          Text(TextesAssistant.mentionAnthropic, style: petit),
        ],
      ),
    );

    // Pied fixé sous la partie qui défile : « Envoyer » reste visible, même
    // à 200 % ou clavier ouvert.
    final pied = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ligneTours, style: petit),
                    if (resteConversation != null &&
                        resteConversation > 0 &&
                        resteConversation <= 3)
                      Text(
                        TextesAssistant.toursConversation(
                          resteConversation,
                          limiteConversation!,
                        ),
                        style: petit,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: peutEnvoyer
                    ? () => unawaited(c.envoyer(widget.contexte))
                    : null,
                child: c.appelEnCours == ModeAssistant.tour
                    ? const IndicateurBouton(label: TextesAssistant.envoi)
                    : const Text(TextesAssistant.envoyer),
              ),
            ],
          ),
          if (offline)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                TextesAssistant.horsLigne,
                textAlign: TextAlign.end,
                style: petit,
              ),
            ),
        ],
      ),
    );

    final resumeCalculs = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(widget.resumeCalculs, style: theme.textTheme.titleSmall),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Petite hauteur ou grand texte (360 × 640 à 200 %) : tout défile d'un
        // bloc sous l'en-tête, rien ne déborde ; sinon le champ et « Envoyer »
        // restent fixés en bas.
        final echelle = MediaQuery.textScalerOf(context).scale(1);
        final compact =
            !constraints.maxHeight.isFinite ||
            constraints.maxHeight < 360 * echelle;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              enTete,
              Expanded(
                child: conversation(
                  avant: [resumeCalculs, const SizedBox(height: 8)],
                  apres: [const Divider(height: 1), bas, pied],
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            enTete,
            resumeCalculs,
            Expanded(child: conversation()),
            const Divider(height: 1),
            // Le champ et ce qui l'entoure défilent quand la place manque
            // (clavier) : la conversation garde de la hauteur.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.45,
              ),
              child: SingleChildScrollView(child: bas),
            ),
            pied,
          ],
        );
      },
    );
  }
}
