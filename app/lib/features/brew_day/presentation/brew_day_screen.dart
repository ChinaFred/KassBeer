import 'dart:async';

import 'package:brewing/brewing.dart'
    show StepEvent, StepEventKind, StepStatus, readTimer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/menu_compte.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/presentation/zone_capture.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/services/screen_wakelock.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/access_providers.dart';
import '../../brews/data/brews_repository.dart';
import '../../brews/domain/brew.dart';
import '../../brews/domain/brew_event.dart';
import '../../brews/domain/deroule.dart';
import '../../brews/presentation/brews_providers.dart';
import '../../brews/presentation/embouteillage.dart';
import '../../costs/data/figeage_embouteillage.dart';
import '../../costs/presentation/costs_providers.dart';
import '../../recipes/domain/chronologie.dart';
import '../../recipes/presentation/contenu_recette.dart';
import '../domain/plan_du_jour.dart';
import 'chronologie_jour.dart';
import 'indicateur_envoi.dart';
import 'mesure_form.dart';

/// Message d'un brassin dont le brassage est fini.
const kBrassageTermine = 'Le brassage de ce brassin est terminé.';

/// Valeur de `extra` du routeur quand l'écran rouvre au lancement (D-Q3).
const kRepriseBrassage = 'reprise';

/// Second appui ignoré en deçà de ce délai : un double appui n'écrit qu'un
/// événement (JB5).
const kDoubleAppui = Duration(milliseconds: 800);

/// Fenêtre de déclenchement de l'alerte : un minuteur fini depuis plus longtemps
/// (écran rouvert, retour d'arrière-plan) ne sonne pas.
const kFenetreAlerte = Duration(seconds: 5);

final _textesJour = TextesDocument(
  chargement: 'Chargement du brassin',
  lectureImpossible: 'Impossible de lire les brassins.',
  absent: 'Ce brassin n\'existe pas ou a été supprimé.',
  horsLigne:
      'Brassin indisponible hors ligne. Préparez le brassage avec du réseau '
      'avant de couper la connexion.',
  illisible: textesBrassin.illisible,
  retour: 'Revenir aux brassins',
);

final _textesJournee = TextesDocument(
  chargement: 'Chargement du brassin',
  lectureImpossible: 'Impossible de lire les brassins.',
  absent: 'Ce brassin n\'existe pas ou a été supprimé.',
  horsLigne:
      'Brassin indisponible hors ligne. Préparez la journée avec du réseau '
      'avant de couper la connexion.',
  illisible: textesBrassin.illisible,
  retour: 'Revenir aux brassins',
);

/// Textes de « Préparer la journée » et de l'écran d'une journée 2 ou suivante
/// (ADR-010).
abstract final class TextesJournee {
  static const titre = 'Journée';
  static const notOwner = 'Seul le brasseur de ce brassin suit cette journée.';
  static const apresBrassage =
      'Cette journée s\'ouvre après la fin du brassage.';
  static const terminee = 'Cette journée est terminée.';
  static const brassinTermine = 'Ce brassin est terminé.';
  static const brassinAbandonne =
      'Ce brassin est abandonné. Reprenez-le pour suivre cette journée.';
  static const inconnue =
      'Cette journée n\'existe pas dans le déroulé de ce brassin.';
  static const preparerSurTelephone =
      'Préparez la journée sur le téléphone qui servira.';
  static const prixLus =
      'Lus sur l\'appareil : le coût se figera à l\'embouteillage.';
  static const prixIndisponibles =
      'Prix indisponibles sur cet appareil hors ligne. Le coût ne se figera '
      'pas.';
  static const saisiesIllisibles = 'Impossible de lire les saisies.';
  static const commencer = 'Commencer la journée';
  static const reprendre = 'Reprendre la journée';
  static const terminer = 'Terminer la journée';
  static const continuer = 'Continuer la journée';
  static const embouteiller = 'Embouteiller';
  static const revenir = 'Revenir au brassin';
  static const toutFait = 'Toutes les étapes sont faites. Journée terminée.';
  static const terminerMessage =
      'Les étapes non commencées seront marquées sautées. Vous pourrez encore '
      'corriger les mesures.';
  static const embouteillerTitre = 'Embouteiller maintenant ?';
  static const embouteillerMessage =
      'Les étapes non commencées resteront non faites.';
  static const embouteillerEnCoursMessage =
      'L\'étape en cours se termine. Les étapes non commencées resteront non '
      'faites.';
  static String prevueLe(DateTime date) =>
      'Prévue le ${formatJourMois(date)}. Vous pouvez la commencer '
      'aujourd\'hui.';
  static String nonTerminee(String nom) =>
      'La journée « $nom » n\'est pas terminée. Ses étapes resteront non '
      'faites.';
  static String terminerTitre(String nom) => 'Terminer la journée « $nom » ?';
  static String journeeTerminee(String nom) => 'Journée « $nom » terminée.';
  static String preparer(String nom) => 'Préparer la journée « $nom »';
  static String reprendreNom(String nom) => 'Reprendre la journée « $nom »';
}

/// Textes de « Se déconnecter » avec des saisies en attente du réseau.
abstract final class TextesDeconnexion {
  static const titre = 'Se déconnecter ?';
  static const rester = 'Rester connecté';
  static const deconnecter = 'Se déconnecter';

  /// « 1 saisie attend le réseau… » ou « N saisies attendent le réseau… ».
  static String message(int n) => n == 1
      ? '1 saisie attend le réseau. Si vous vous déconnectez maintenant, elle '
            'risque de ne jamais partir.'
      : '$n saisies attendent le réseau. Si vous vous déconnectez maintenant, '
            'elles risquent de ne jamais partir.';
}

/// « Se déconnecter ? » quand [enAttente] saisies du jour n'ont pas encore
/// rejoint le serveur : vrai si l'utilisateur se déconnecte. Firestore garde
/// ces écritures sous le compte qui les a faites ; elles ne partent qu'à la
/// reconnexion du même compte sur cet appareil.
Future<bool> confirmerDeconnexionSaisies(BuildContext context, int enAttente) =>
    // ticket: aucun (confirmation)
    confirmerAbandon(
      context,
      TextesDeconnexion.message(enAttente),
      titre: TextesDeconnexion.titre,
      continuer: TextesDeconnexion.rester,
      abandonner: TextesDeconnexion.deconnecter,
    );

/// Raison d'une journée qui ne se suit pas, avec son icône.
typedef RefusJournee = ({IconData icon, String message});

/// Journée [key] de [brew] à suivre (ADR-010), ou la raison du refus : déroulé
/// illisible, clé inconnue, brassage pas fini, brassin terminé ou abandonné,
/// embouteillage fait. Ni journée ni refus : [key] est la journée de brassage,
/// qui se suit par « Préparer le brassage ». Le propriétaire se vérifie avant.
({JourneeDeroulee? journee, RefusJournee? refus}) journeeASuivre(
  Brew brew,
  String key,
) {
  final deroule = brew.deroule;
  final illisible = messageDerouleIllisible(deroule);
  if (illisible != null) {
    return (
      journee: null,
      refus: (icon: Icons.error_outline, message: illisible),
    );
  }
  final journee = deroule.journee(key);
  if (journee == null) {
    return (
      journee: null,
      refus: (icon: Icons.search_off, message: TextesJournee.inconnue),
    );
  }
  if (journee.role == RoleJournee.brassage) return (journee: null, refus: null);
  final RefusJournee? refus = switch (brew.status) {
    BrewStatus.planned || BrewStatus.brewing => (
      icon: Icons.schedule,
      message: TextesJournee.apresBrassage,
    ),
    BrewStatus.done => (
      icon: Icons.check_circle_outline,
      message: TextesJournee.brassinTermine,
    ),
    BrewStatus.abandoned => (
      icon: Icons.block,
      message: TextesJournee.brassinAbandonne,
    ),
    _
        when journee.role == RoleJournee.embouteillage &&
            brew.bottledAt != null =>
      (icon: Icons.check_circle_outline, message: TextesJournee.terminee),
    _ => null,
  };
  return (journee: refus == null ? journee : null, refus: refus);
}

/// Écran du jour de brassage (`/brassins/:id/jour`), réservé au propriétaire,
/// ou d'une journée 2 ou suivante du déroulé (`/brassins/:id/jour/:journee`,
/// ADR-010).
///
/// Marche sans réseau (CLAUDE.md, P2) : aucune transaction, aucune requête ;
/// chaque début, fin et mesure est un événement. Le minuteur se recalcule depuis
/// l'heure enregistrée : le `Timer` ne fait que redessiner.
class BrewDayScreen extends ConsumerWidget {
  const BrewDayScreen({
    super.key,
    required this.id,
    this.reprise = false,
    this.journee,
  });

  final String id;

  /// Clé de la journée suivie ; `null` (ou la clé de la journée de brassage)
  /// pour le brassage.
  final String? journee;

  /// Écran rouvert au lancement : annonce unique.
  final bool reprise;

  static const notOwner = 'Seul le brasseur de ce brassin suit son brassage.';
  static const reprised =
      'Brassage repris. Les minuteurs comptent le temps écoulé.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(grantedAccessProvider);
    return PageDocument<Brew>(
      async: ref.watch(brewsListProvider),
      id: id,
      offline: access?.offline ?? false,
      textes: journee == null ? _textesJour : _textesJournee,
      onRetry: () => ref.invalidate(brewsListProvider),
      onBack: () => context.go(AppRoutes.brews),
      frame: (state) => Scaffold(
        appBar: AppBar(
          title: Text(
            journee == null ? 'Jour de brassage' : TextesJournee.titre,
          ),
          actions: const [MenuCompte(photo: false), SizedBox(width: 8)],
        ),
        body: ZoneCapture(child: SafeArea(child: state)),
      ),
      builder: (context, brew) {
        final cle = journee;
        if (cle != null) {
          if (brew.ownerUid != access?.user.uid) {
            return _Message(
              icon: Icons.lock_outline,
              message: TextesJournee.notOwner,
              action: 'Voir le brassin',
              path: AppRoutes.brew(id),
              titre: TextesJournee.titre,
            );
          }
          final suivie = journeeASuivre(brew, cle);
          final refus = suivie.refus;
          if (refus != null) {
            return _Message(
              icon: refus.icon,
              message: refus.message,
              action: 'Voir le brassin',
              path: AppRoutes.brew(id),
              titre: TextesJournee.titre,
            );
          }
          final j = suivie.journee;
          if (j != null) {
            return _EcranJour(
              key: ValueKey('$id/${j.key}'),
              brew: brew,
              reprise: false,
              journee: j,
            );
          }
        }
        if (brew.ownerUid != access?.user.uid) {
          return _Message(
            icon: Icons.lock_outline,
            message: notOwner,
            action: 'Voir le brassin',
            path: AppRoutes.brew(id),
          );
        }
        if (brew.status == BrewStatus.planned) {
          return _Message(
            icon: Icons.schedule,
            message: 'Ce brassin n\'a pas commencé.',
            action: 'Préparer le brassage',
            path: AppRoutes.prepareBrew(id),
          );
        }
        if (brew.status != BrewStatus.brewing) {
          return _Message(
            icon: Icons.check_circle_outline,
            message: kBrassageTermine,
            action: 'Voir le brassin',
            path: AppRoutes.brew(id),
          );
        }
        return _EcranJour(key: ValueKey(id), brew: brew, reprise: reprise);
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.message,
    required this.action,
    required this.path,
    this.titre = 'Jour de brassage',
  });

  final IconData icon;
  final String message;
  final String action;
  final String path;
  final String titre;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(titre),
        actions: const [MenuCompte(photo: false), SizedBox(width: 8)],
      ),
      body: ZoneCapture(
        child: SafeArea(
          child: EtatVide(
            icon: icon,
            message: message,
            action: FilledButton(
              onPressed: () => context.go(path),
              child: Text(action),
            ),
          ),
        ),
      ),
    );
  }
}

class _EcranJour extends ConsumerStatefulWidget {
  const _EcranJour({
    super.key,
    required this.brew,
    required this.reprise,
    this.journee,
  });

  final Brew brew;
  final bool reprise;

  /// Journée 2 ou suivante suivie ; `null` pour le brassage.
  final JourneeDeroulee? journee;

  @override
  ConsumerState<_EcranJour> createState() => _EcranJourState();
}

class _EcranJourState extends ConsumerState<_EcranJour>
    with KeepScreenAwake<_EcranJour> {
  Timer? _ticker;
  final _alertedSteps = <String>{};
  final _refus = <SaisieRefusee>[];
  DateTime? _lastAction;
  MeasureType? _lastType;
  late final Future<String?> _tokenName;
  String? _etapeAnnoncee;
  bool _etapeConnue = false;

  /// Journée « autre » vue terminée au dernier calcul ; `null` avant le premier.
  bool? _termineeVue;

  Brew get _brew => widget.brew;
  JourneeDeroulee? get _journee => widget.journee;
  DateTime _now() => ref.read(horlogeProvider)();

  /// Étapes de la journée suivie.
  List<BrewStepLine> get _lignes =>
      (_journee ?? _brew.deroule.brassage)?.lignes ?? const [];

  /// Saisies d'une journée 2 ou suivante : relevé de fermentation (ADR-010).
  PhaseEvenement? get _phase =>
      _journee == null ? null : PhaseEvenement.fermentation;

  @override
  void initState() {
    super.initState();
    // Lu une fois à l'ouverture (3 s au plus), réutilisé ensuite : le statut ne
    // l'attend pas à chaque appui (règle owner_name).
    _tokenName = ref.read(authRepositoryProvider).currentTokenName();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    if (widget.reprise) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(BrewDayScreen.reprised)));
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Redessine l'écran ; aucune durée n'en dépend (P2). Vérifie aussi l'alerte de
  /// fin de minuteur.
  void _tick() {
    if (!mounted) return;
    setState(() {});
    final evalue = _evaluer();
    if (evalue is PlanObtenu) {
      _annoncerEtape(evalue.plan);
      _verifierAlerte(evalue.plan);
      _annoncerFinJournee(evalue.plan);
    }
  }

  /// « Journée « {nom} » terminée. » quand la dernière étape d'une journée
  /// « autre » se termine pendant que l'écran est ouvert ; rien à l'ouverture.
  void _annoncerFinJournee(PlanDuJour plan) {
    final journee = _journee;
    if (journee == null || journee.role != RoleJournee.autre) return;
    final terminee = plan.termine;
    final avant = _termineeVue;
    _termineeVue = terminee;
    if (avant == false && terminee) {
      _annoncer(TextesJournee.journeeTerminee(journee.name.trim()));
    }
  }

  /// Une annonce au changement d'étape en cours ; aucune à l'ouverture.
  void _annoncerEtape(PlanDuJour plan) {
    final ligne = plan.enCours;
    final key = ligne?.step.key;
    final previous = _etapeAnnoncee;
    _etapeAnnoncee = key;
    if (ligne == null || !_etapeConnue || previous == key) {
      _etapeConnue = true;
      return;
    }
    _annoncer('Étape en cours : ${ligne.step.name}.');
  }

  void _annoncer(String message) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        TextDirection.ltr,
      ),
    );
  }

  void _verifierAlerte(PlanDuJour plan) {
    final ligne = plan.enCours;
    final started = ligne?.record?.startedAt;
    if (ligne == null || started == null) return;
    final reading = readTimer(
      startedAt: started,
      duration: ligne.duree,
      now: _now(),
    );
    if (!reading.isFinished || _alertedSteps.contains(ligne.step.key)) return;
    _alertedSteps.add(ligne.step.key);
    if (reading.overrun > kFenetreAlerte) return;
    _annoncer('Durée dépassée : ${ligne.step.name}.');
    unawaited(ref.read(alerteMinuteurProvider).declencher());
  }

  List<BrewEvent> _lire(ListeLue<BrewEvent>? list) => [...?list?.valides];

  PlanEvalue _evaluer() => evaluerPlan(
    brew: _brew,
    events: _lire(ref.read(brewEventsProvider(_brew.id)).value),
    now: _now(),
    errors: ref.read(errorReportServiceProvider),
    reported: ref.read(planReportsProvider),
    journee: _journee,
  );

  bool _premierAppui() {
    final now = _now();
    final last = _lastAction;
    if (last != null && now.difference(last) < kDoubleAppui) return false;
    _lastAction = now;
    return true;
  }

  /// Suit la réponse du serveur : un refus s'affiche jusqu'à la fermeture (HS7).
  /// Le dépôt ne fait échouer [written] que si l'événement n'est pas sur le serveur.
  void _suivre(
    Future<void> written,
    String libelle, {
    VoidCallback? reprendre,
  }) {
    unawaited(
      written.catchError((Object _) {
        // Déjà rapportée par le dépôt de données.
        if (mounted) {
          setState(
            () => _refus.add(
              SaisieRefusee(libelle: libelle, reprendre: reprendre),
            ),
          );
        }
      }),
    );
  }

  Future<void> _ecrire(List<StepWrite> writes, String libelle) async {
    _suivre(
      ref
          .read(brewsRepositoryProvider)
          .writeSteps(
            brewId: _brew.id,
            ownerUid: _brew.ownerUid,
            writes: writes,
            at: _now(),
          ),
      libelle,
    );
  }

  Future<bool> _confirmer(
    String titre,
    String message,
    String oui, {
    String non = 'Annuler',
  }) async {
    // ticket: aucun (confirmation)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titre),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(non),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(oui),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _commencer(LigneJour ligne, PlanDuJour plan) async {
    final running = plan.enCours;
    final avant = plan.nonFaitesAvant(ligne);
    final writes = <StepWrite>[];
    if (running != null && running.step.key != ligne.step.key) {
      final ok = await _confirmer(
        '« ${running.step.name} » est en cours.',
        'Terminer cette étape pour commencer « ${ligne.step.name} » ?',
        'Terminer et commencer',
      );
      if (!ok || !mounted) return;
      writes.add((kind: StepEventKind.ended, stepKey: running.step.key));
    } else if (avant.isNotEmpty) {
      final ok = await _confirmer(
        avant.length == 1
            ? '1 étape avant celle-ci n\'est pas faite'
            : '${avant.length} étapes avant celle-ci ne sont pas faites',
        avant.map((l) => l.step.name).join(', '),
        'Les sauter et commencer',
      );
      if (!ok || !mounted) return;
      // Écritures simples, l'une après l'autre : un lot de plus de 20 événements
      // ferait plus de 20 `get()` dans les règles, refusé en production.
      for (final l in avant) {
        await _ecrire([
          (kind: StepEventKind.skipped, stepKey: l.step.key),
        ], 'Saut de « ${l.step.name} »');
      }
    } else if (!_premierAppui()) {
      return;
    }
    ref.read(alerteMinuteurProvider).preparer();
    writes.add((kind: StepEventKind.started, stepKey: ligne.step.key));
    if (ligne.step.durationMin == 0) {
      writes.add((kind: StepEventKind.ended, stepKey: ligne.step.key));
    }
    await _ecrire(writes, 'Début de « ${ligne.step.name} »');
  }

  void _terminerEtape(LigneJour ligne) {
    if (!_premierAppui()) return;
    unawaited(
      _ecrire([
        (kind: StepEventKind.ended, stepKey: ligne.step.key),
      ], 'Fin de « ${ligne.step.name} »'),
    );
  }

  Future<void> _terminerBrassage() async {
    final ok = await _confirmer(
      'Terminer le brassage ?',
      'Les étapes non commencées resteront non faites. Vous pourrez encore '
          'corriger les mesures.',
      'Terminer le brassage',
      non: 'Continuer le brassage',
    );
    if (!ok || !mounted) return;
    final router = GoRouter.of(context);
    final ownerName = await _tokenName;
    if (!mounted) return;
    _suivre(
      ref
          .read(brewsRepositoryProvider)
          .finish(brewId: _brew.id, ownerName: ownerName),
      'Fin du brassage',
    );
    router.go(AppRoutes.brew(_brew.id));
  }

  /// « Terminer la journée » (ADR-010) : `step_ended` pour l'étape en cours et
  /// `step_skipped` pour chaque étape à venir, dans un `WriteBatch`, sans
  /// changement de statut. Confirmation s'il reste des étapes à venir.
  Future<void> _terminerJournee(PlanDuJour? plan) async {
    final journee = _journee;
    if (journee == null || plan == null) return;
    final nom = journee.name.trim();
    final avenir = [
      for (final l in plan.lignes)
        if (l.status == StepStatus.pending) l,
    ];
    if (avenir.isNotEmpty) {
      final ok = await _confirmer(
        TextesJournee.terminerTitre(nom),
        TextesJournee.terminerMessage,
        TextesJournee.terminer,
        non: TextesJournee.continuer,
      );
      if (!ok || !mounted) return;
    } else if (!_premierAppui()) {
      return;
    }
    final running = plan.enCours;
    final writes = <StepWrite>[
      if (running != null)
        (kind: StepEventKind.ended, stepKey: running.step.key),
      for (final l in avenir)
        (kind: StepEventKind.skipped, stepKey: l.step.key),
    ];
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    if (writes.isNotEmpty) {
      await _ecrire(writes, 'Fin de la journée « $nom »');
    }
    router.go(AppRoutes.brew(_brew.id));
    messenger.showSnackBar(
      SnackBar(content: Text(TextesJournee.journeeTerminee(nom))),
    );
  }

  /// « Embouteiller » depuis la journée d'embouteillage (ADR-010) : confirmation
  /// s'il reste des étapes, puis le formulaire d'embouteillage de la fiche. À
  /// l'envoi, l'étape en cours se termine ([_envoyerEmbouteillage]).
  Future<void> _embouteiller(PlanDuJour? plan) async {
    final reste =
        plan != null && (plan.enCours != null || plan.prochaine != null);
    if (reste) {
      final ok = await _confirmer(
        TextesJournee.embouteillerTitre,
        plan.enCours != null
            ? TextesJournee.embouteillerEnCoursMessage
            : TextesJournee.embouteillerMessage,
        TextesJournee.embouteiller,
        non: TextesJournee.continuer,
      );
      if (!ok || !mounted) return;
    }
    final events = _lire(ref.read(brewEventsProvider(_brew.id)).value);
    unawaited(
      // ticket: /brassins/:id/jour/:journee/fenetre/embouteillage
      showFeuilleOuDialogue<void>(
        context: context,
        fermetureProtegee: true,
        builder: (_) => FormulaireEmbouteillage(
          brew: _brew,
          modification: false,
          fermentationMesuree: densiteDeFermentationMesuree(events),
          now: _now,
          onSubmit: (embouteillage, finalGravity) =>
              unawaited(_envoyerEmbouteillage(embouteillage, finalGravity)),
        ),
      ),
    );
  }

  /// Envoie l'embouteillage avec les prix, les frais et le coût figé ouverts à
  /// « Préparer la journée » (P2, CB5), puis rend la main à la fiche, qui
  /// annonce le résultat comme pour un embouteillage fait depuis elle. L'étape
  /// en cours reçoit son `step_ended` à l'heure de l'envoi, sans attendre le
  /// serveur : `enregistrerEmbouteillage` n'écrit aucune étape.
  Future<void> _envoyerEmbouteillage(
    Embouteillage embouteillage,
    double? finalGravity,
  ) async {
    final envoyer = capturerEmbouteillage(ref, _brew);
    final offline = ref.read(grantedAccessProvider)?.offline ?? false;
    final annonces = ref.read(embouteillagesAAnnoncerProvider);
    final router = GoRouter.of(context);
    final brewId = _brew.id;
    final enCours = switch (_evaluer()) {
      PlanObtenu(:final plan) => plan.enCours,
      PlanImpossible() => null,
    };
    if (enCours != null) {
      await _ecrire([
        (kind: StepEventKind.ended, stepKey: enCours.step.key),
      ], 'Fin de « ${enCours.step.name} »');
    }
    final ownerName = await _tokenName;
    final envoi = envoyer(
      embouteillage: embouteillage,
      finalGravity: finalGravity,
      modification: false,
      ownerName: ownerName,
    );
    // La fiche annonce le résultat à son retour. Si elle ne s'affiche pas, aucun
    // refus ne reste sans écouteur : il est déjà rapporté par le dépôt de
    // données (`brews.*`, `costs.freeze_rejected`), rien n'est rapporté de plus.
    unawaited(envoi.embouteillage.catchError((Object _) {}));
    final cout = envoi.cout;
    if (cout is CoutFigeEnvoye) {
      unawaited(cout.written.catchError((Object _) {}));
    }
    annonces[brewId] = (envoi: envoi, offline: offline);
    router.go(AppRoutes.brew(brewId));
  }

  void _ouvrirMesure({
    String? stepKey,
    MeasureType? type,
    bool note = false,
    double? initialValue,
    DateTime? initialAt,
    String? initialNote,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      // ticket: /brassins/:id/jour/fenetre/mesure, /brassins/:id/jour/:journee/fenetre/mesure
      showFeuilleOuDialogue<void>(
        context: context,
        fermetureProtegee: true,
        builder: (_) => FormulaireMesure(
          steps: _lignes,
          releve: _journee != null,
          bottledAt: _brew.bottledAt,
          initialStepKey: stepKey,
          initialType: type ?? _lastType ?? MeasureType.temperature,
          note: note,
          now: _now,
          initialValue: initialValue,
          initialAt: initialAt,
          initialNote: initialNote,
          plancher: _brew.brewedAt,
          onSubmit: (saisie) {
            if (saisie.type != null) _lastType = saisie.type;
            enregistrerSaisie(
              ref: ref,
              messenger: messenger,
              brew: _brew,
              saisie: saisie,
              phase: _phase,
              suivre: (written, libelle) => _suivre(
                written,
                libelle,
                reprendre: saisie.kind == BrewEventKind.measurement
                    ? () => _ouvrirMesure(
                        stepKey: saisie.stepKey,
                        type: saisie.type,
                        initialValue: saisie.value,
                        initialAt: saisie.at,
                        initialNote: saisie.note,
                      )
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }

  /// Type par défaut d'une mesure pour [ligne] : température si l'étape en vise une.
  MeasureType? _typeParDefaut(LigneJour? ligne) =>
      ligne?.step.tempC != null ? MeasureType.temperature : null;

  void _feuilleEtape(LigneJour ligne, PlanDuJour plan) {
    final record = ligne.record;
    final started = record?.startedAt;
    final ended = record?.endedAt;
    final skipIds = record?.skipEventIds ?? const <String>[];
    final startId = record?.startEventId;
    final endId = record?.endEventId;
    final status = ligne.status;

    void item(List<Widget> items, String label, VoidCallback action) {
      items.add(
        ListTile(
          minTileHeight: 64,
          title: Text(label),
          onTap: () {
            Navigator.of(context).pop();
            action();
          },
        ),
      );
    }

    final items = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Semantics(
          header: true,
          child: Text(
            '${ligne.step.name} · ${libelleEtat(status)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ),
    ];
    if (started == null) {
      item(items, 'Commencer cette étape', () => _commencer(ligne, plan));
      if (status == StepStatus.skipped) {
        item(items, 'Ne plus sauter', () {
          for (final id in skipIds) {
            _suivre(
              ref
                  .read(brewsRepositoryProvider)
                  .deleteEvent(brewId: _brew.id, eventId: id),
              'Annulation du saut',
            );
          }
        });
      } else {
        item(items, 'Marquer comme sautée', () {
          unawaited(
            _ecrire([
              (kind: StepEventKind.skipped, stepKey: ligne.step.key),
            ], 'Saut de « ${ligne.step.name} »'),
          );
        });
      }
    } else {
      item(items, 'Corriger l\'heure de début', () => _corrigerDebut(ligne));
      if (ended != null) {
        item(items, 'Corriger l\'heure de fin', () => _corrigerFin(ligne));
      }
      if (endId != null) {
        item(
          items,
          'Annuler la fin',
          () => _annuler(ligne, endId, ended!, StepEventKind.ended, 'La fin'),
        );
      } else if (startId != null) {
        item(
          items,
          'Annuler le début',
          () => _annuler(
            ligne,
            startId,
            started,
            StepEventKind.started,
            'Le début',
          ),
        );
      }
    }
    item(
      items,
      'Saisir une mesure pour cette étape',
      () => _ouvrirMesure(stepKey: ligne.step.key, type: _typeParDefaut(ligne)),
    );
    unawaited(
      // ticket: /brassins/:id/jour/fenetre/etape, /brassins/:id/jour/:journee/fenetre/etape
      showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (context) => SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: items),
        ),
      ),
    );
  }

  Future<void> _corrigerDebut(LigneJour ligne) async {
    final record = ligne.record!;
    final choix = await demanderHeure(
      context,
      base: record.startedAt!,
      now: _now(),
      plancher: _brew.brewedAt,
    );
    if (choix == null || !mounted) return;
    final at = choix.at;
    if (at == null) {
      _message(choix.erreur!);
      return;
    }
    final end = record.endedAt;
    if (end != null && at.isAfter(end)) {
      _message(kFinAvantDebut);
      return;
    }
    _suivre(
      ref
          .read(brewsRepositoryProvider)
          .correct(
            brewId: _brew.id,
            eventId: record.startEventId!,
            value: null,
            note: null,
            measuredAt: at,
          ),
      'Correction de « ${ligne.step.name} »',
    );
  }

  Future<void> _corrigerFin(LigneJour ligne) async {
    final record = ligne.record!;
    final choix = await demanderHeure(
      context,
      base: record.endedAt!,
      now: _now(),
      apres: record.startedAt,
      plancher: _brew.brewedAt,
    );
    if (choix == null || !mounted) return;
    final at = choix.at;
    if (at == null) {
      _message(choix.erreur!);
      return;
    }
    _suivre(
      ref
          .read(brewsRepositoryProvider)
          .correct(
            brewId: _brew.id,
            eventId: record.endEventId!,
            value: null,
            note: null,
            measuredAt: at,
          ),
      'Correction de « ${ligne.step.name} »',
    );
  }

  /// Annule le début ou la fin ; « Annuler » réécrit le même identifiant (JB8).
  void _annuler(
    LigneJour ligne,
    String eventId,
    DateTime at,
    StepEventKind kind,
    String quoi,
  ) {
    final repo = ref.read(brewsRepositoryProvider);
    _suivre(
      repo.deleteEvent(brewId: _brew.id, eventId: eventId),
      '$quoi de « ${ligne.step.name} »',
    );
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        persist: false,
        content: Text(
          kind == StepEventKind.ended
              ? 'La fin est annulée.'
              : 'Le début est annulé.',
        ),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () => _suivre(
            repo.restoreEvent(
              brewId: _brew.id,
              event: BrewEvent(
                id: eventId,
                ownerUid: _brew.ownerUid,
                kind: switch (kind) {
                  StepEventKind.started => BrewEventKind.started,
                  StepEventKind.ended => BrewEventKind.ended,
                  StepEventKind.skipped => BrewEventKind.skipped,
                },
                stepKey: ligne.step.key,
                measuredAt: at,
              ),
            ),
            'Rétablissement de « ${ligne.step.name} »',
          ),
        ),
      ),
    );
  }

  void _supprimerDoublon(StepEvent event) => _suivre(
    ref
        .read(brewsRepositoryProvider)
        .deleteEvent(brewId: _brew.id, eventId: event.id),
    'Début en double',
  );

  void _message(String texte) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(texte)));

  void _voirRecette() {
    unawaited(
      // ticket: /brassins/:id/jour/fenetre/recette, /brassins/:id/jour/:journee/fenetre/recette
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                _brew.recipe.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              ContenuRecette(content: _brew.recipe),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(brewEventsProvider(_brew.id));
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final journee = _journee;
    if (journee?.role == RoleJournee.embouteillage) {
      // Lectures ouvertes à « Préparer la journée », gardées pour
      // l'embouteillage (P2) : aucune lecture ne part à l'envoi.
      final uid = _brew.ownerUid;
      ref.watch(pricesProvider(uid));
      ref.watch(feesProvider(uid));
      ref.watch(brewCostProvider((uid: uid, brewId: _brew.id)));
    }
    final list = eventsAsync.value;
    void retour() => context.go(AppRoutes.brew(_brew.id));
    if (list == null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) retour();
        },
        child: Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: retour),
            title: Text(_brew.name),
            actions: const [MenuCompte(photo: false), SizedBox(width: 8)],
          ),
          body: ZoneCapture(
            child: eventsAsync.hasError
                ? EtatErreur(
                    message: 'Impossible de lire les saisies.',
                    onRetry: () => ref.invalidate(brewEventsProvider(_brew.id)),
                  )
                : const EtatChargement(label: 'Chargement du brassin'),
          ),
        ),
      );
    }
    final now = _now();
    final evalue = _evaluer();
    final PlanDuJour? plan = switch (evalue) {
      PlanObtenu(:final plan) => plan,
      PlanImpossible() => null,
    };
    return _Jour(
      brew: _brew,
      journee: journee,
      plan: plan,
      verrouRefuse: wakelock.failed,
      now: now,
      events: _lire(list),
      offline: offline,
      refus: _refus,
      onTerminerEtape: _terminerEtape,
      onCommencer: (l, p) => unawaited(_commencer(l, p)),
      onMesure: (ligne) =>
          _ouvrirMesure(stepKey: ligne?.step.key, type: _typeParDefaut(ligne)),
      onNote: () => _ouvrirMesure(note: true, stepKey: plan?.enCours?.step.key),
      onTapLigne: (l, p) => _feuilleEtape(l, p),
      onTapSaisie: (event) => ouvrirCorrection(
        context: context,
        ref: ref,
        brew: _brew,
        event: event,
        suivre: _suivre,
      ),
      onSupprimerDoublon: _supprimerDoublon,
      onTerminerBrassage: () => unawaited(_terminerBrassage()),
      onTerminerJournee: () => unawaited(_terminerJournee(plan)),
      onEmbouteiller: () => unawaited(_embouteiller(plan)),
      onVoirRecette: _voirRecette,
      onRetour: retour,
    );
  }
}

/// Mise en page de l'écran du jour, sans état.
class _Jour extends StatelessWidget {
  const _Jour({
    required this.brew,
    required this.journee,
    required this.plan,
    required this.verrouRefuse,
    required this.now,
    required this.events,
    required this.offline,
    required this.refus,
    required this.onTerminerEtape,
    required this.onCommencer,
    required this.onMesure,
    required this.onNote,
    required this.onTapLigne,
    required this.onTapSaisie,
    required this.onSupprimerDoublon,
    required this.onTerminerBrassage,
    required this.onTerminerJournee,
    required this.onEmbouteiller,
    required this.onVoirRecette,
    required this.onRetour,
  });

  final Brew brew;

  /// Journée 2 ou suivante ; `null` pour le brassage.
  final JourneeDeroulee? journee;
  final PlanDuJour? plan;
  final ValueListenable<bool> verrouRefuse;
  final DateTime now;
  final List<BrewEvent> events;
  final bool offline;
  final List<SaisieRefusee> refus;
  final void Function(LigneJour) onTerminerEtape;
  final void Function(LigneJour, PlanDuJour) onCommencer;
  final void Function(LigneJour?) onMesure;
  final VoidCallback onNote;
  final void Function(LigneJour, PlanDuJour) onTapLigne;
  final void Function(BrewEvent) onTapSaisie;
  final void Function(StepEvent) onSupprimerDoublon;
  final VoidCallback onTerminerBrassage;
  final VoidCallback onTerminerJournee;
  final VoidCallback onEmbouteiller;
  final VoidCallback onVoirRecette;
  final VoidCallback onRetour;

  @override
  Widget build(BuildContext context) {
    final styles = StylesJourDeBrassage.of(context);
    final pending = events.where((e) => e.hasPendingWrites).toList();
    final mesures = pending.where((e) => e.isMeasureOrNote).length;
    final etapes = pending.length - mesures;
    final detail = [
      if (mesures > 0) '$mesures mesure${mesures > 1 ? 's' : ''}',
      if (etapes > 0) '$etapes étape${etapes > 1 ? 's' : ''}',
    ].join(', ');

    // Avec un processus, la barre nomme la journée (ADR-010) ; sans processus,
    // elle garde l'heure seule.
    final suivie = this.journee;
    final journee = suivie != null
        ? suivie.name.trim()
        : brew.process == null
        ? null
        : brew.deroule.brassage?.name.trim();
    final role = suivie?.role;
    final reste =
        plan != null && (plan!.enCours != null || plan!.prochaine != null);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kCompactMaxWidth;
        final low = constraints.maxHeight < kCompactMaxHeight;
        final twoColumns = wide || low;
        // Hauteur d'abord : un téléphone en paysage dépasse 600 de large.
        final timerSize = low
            ? styles.minuteurPaysage
            : (wide ? styles.minuteurLarge : styles.minuteur);
        final etapeSize = !low && wide ? styles.etapeLarge : styles.etape;
        final panneau = _Panneau(
          plan: plan,
          toutFait: role == RoleJournee.autre
              ? TextesJournee.toutFait
              : 'Toutes les étapes sont faites.',
          illisible: messageDerouleIllisible(brew.deroule),
          now: now,
          timerSize: timerSize,
          etapeSize: etapeSize,
          ensuiteSize: styles.ensuite,
        );
        final chronologie = plan == null
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                child: ChronologieJour(
                  plan: plan!,
                  onTapLigne: (l) => onTapLigne(l, plan!),
                  onTapSaisie: onTapSaisie,
                  onSupprimerDoublon: onSupprimerDoublon,
                ),
              );
        final barre = _BarreActions(
          plan: plan,
          role: role,
          onMesure: onMesure,
          onTerminerEtape: onTerminerEtape,
          onCommencer: onCommencer,
          onTerminerBrassage: onTerminerBrassage,
          onTerminerJournee: onTerminerJournee,
          onEmbouteiller: onEmbouteiller,
          onRetour: onRetour,
          height: low ? 64 : 72,
        );
        final Widget body;
        if (twoColumns) {
          body = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 55,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [panneau],
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 45,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: kBrewDayChronologyMaxWidth,
                    ),
                    child: chronologie,
                  ),
                ),
              ),
            ],
          );
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.6,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: panneau,
                ),
              ),
              const Divider(height: 1),
              Expanded(child: chronologie),
            ],
          );
        }
        return PopScope(
          canPop: false,
          // Écran seul dans la pile : le retour Android quitterait l'application.
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) onRetour();
          },
          child: Scaffold(
            appBar: AppBar(
              leading: BackButton(onPressed: onRetour),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(brew.name, overflow: TextOverflow.ellipsis),
                  Semantics(
                    label: journee == null
                        ? 'Heure actuelle ${formatHeure(now)}'
                        : 'Journée $journee, heure actuelle '
                              '${formatHeure(now)}',
                    excludeSemantics: true,
                    child: Text(
                      journee == null
                          ? formatHeure(now)
                          : '$journee · ${formatHeure(now)}',
                      key: const ValueKey('heure-appareil'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              toolbarHeight: low ? 56 : 64,
              actions: [
                IndicateurEnvoi(
                  enAttente: pending.length,
                  horsLigne: offline,
                  refus: refus,
                  detailAttente: detail,
                  web: kIsWeb,
                ),
                // ticket: /brassins/:id/jour/menu/actions, /brassins/:id/jour/:journee/menu/actions
                PopupMenuButton<VoidCallback>(
                  tooltip: 'Plus d\'actions',
                  onSelected: (action) => action(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: onNote,
                      child: const Text('Ajouter une note'),
                    ),
                    PopupMenuItem(
                      value: onVoirRecette,
                      child: const Text('Voir la recette'),
                    ),
                    if (role == null)
                      PopupMenuItem(
                        value: onTerminerBrassage,
                        child: const Text('Terminer le brassage'),
                      )
                    else if (role == RoleJournee.embouteillage)
                      PopupMenuItem(
                        value: onEmbouteiller,
                        child: const Text(TextesJournee.embouteiller),
                      )
                    else if (reste)
                      PopupMenuItem(
                        value: onTerminerJournee,
                        child: const Text(TextesJournee.terminer),
                      ),
                  ],
                ),
                // Initiale seule : aucune image chargée par le réseau (P2).
                MenuCompte(
                  photo: false,
                  avantDeDeconnecter: pending.isEmpty
                      ? null
                      : () => confirmerDeconnexionSaisies(
                          context,
                          pending.length,
                        ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            // En bas de l'écran, toujours visible : les SnackBar s'affichent
            // au-dessus des boutons.
            bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: low ? 8 : 12,
                ),
                child: twoColumns
                    ? Center(
                        heightFactor: 1,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: kBrewDayActionsMaxWidth,
                          ),
                          child: barre,
                        ),
                      )
                    : barre,
              ),
            ),
            body: ZoneCapture(
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: verrouRefuse,
                      builder: (context, refuse, _) => refuse
                          ? Material(
                              color: Theme.of(
                                context,
                              ).colorScheme.errorContainer,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  kVerrouRefuse,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: kBrewDayMaxWidth,
                          ),
                          child: body,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Panneau extends StatelessWidget {
  const _Panneau({
    required this.plan,
    required this.toutFait,
    required this.illisible,
    required this.now,
    required this.timerSize,
    required this.etapeSize,
    required this.ensuiteSize,
  });

  final PlanDuJour? plan;

  /// Texte affiché quand toutes les étapes sont faites.
  final String toutFait;

  /// Texte d'un déroulé illisible ([messageDerouleIllisible]), ou `null`.
  final String? illisible;
  final DateTime now;
  final double timerSize;
  final double etapeSize;
  final double ensuiteSize;

  Widget _texte(
    BuildContext context,
    String text,
    double size, {
    int? maxLines,
  }) => Text(
    text,
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = plan;
    final raison = illisible;
    if (raison != null) {
      return Text(
        raison,
        style: TextStyle(fontSize: ensuiteSize, color: scheme.error),
      );
    }
    if (p == null) {
      return Text(
        kCalculChronologieImpossible,
        style: TextStyle(fontSize: ensuiteSize, color: scheme.error),
      );
    }
    if (p.lignes.isEmpty) {
      return _texte(
        context,
        'Aucune étape. Saisissez vos mesures.',
        ensuiteSize,
      );
    }
    if (p.termine) return _texte(context, toutFait, ensuiteSize);
    final finPrevue = p.finPrevue;
    final ligneFin = finPrevue == null
        ? null
        : 'Fin prévue vers ${formatHeure(finPrevue)}'
              '${p.retard > Duration.zero ? ' · retard ${formatDuree(p.retard)}' : ''}';
    final running = p.enCours;
    if (running == null) {
      final next = p.prochaine!;
      final vers = next.schedule.expectedStart;
      final maintenant = !vers.isAfter(now);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Étape ${next.index + 1} sur ${p.lignes.length}'.toUpperCase(),
            style: theme.textTheme.labelLarge,
          ),
          _texte(
            context,
            next.step.durationMin == 0
                ? 'Action : ${next.step.name}'
                : 'Prochaine étape : ${next.step.name}',
            etapeSize,
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          Text(
            maintenant ? 'Maintenant' : 'Prévue vers ${formatHeure(vers)}',
            style: TextStyle(fontSize: ensuiteSize),
          ),
          Text(
            [
              if (next.step.durationMin > 0) formatDuree(next.duree),
              if (next.step.tempC != null) formatCelsius(next.step.tempC!),
            ].join(' · '),
            style: TextStyle(fontSize: ensuiteSize),
          ),
          if (ligneFin != null) ...[const SizedBox(height: 8), Text(ligneFin)],
        ],
      );
    }
    final reading = readTimer(
      startedAt: running.record!.startedAt!,
      duration: running.duree,
      now: now,
    );
    final depasse = reading.isFinished && reading.overrun > Duration.zero;
    final fini = reading.isFinished;
    final suivante = p.suivanteDe(running);
    final mesure = running.mesures
        .where((m) => m.measureType == MeasureType.temperature)
        .lastOrNull;
    final temp = running.step.tempC;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Étape ${running.index + 1} sur ${p.lignes.length} · En cours'
              .toUpperCase(),
          style: theme.textTheme.labelLarge,
        ),
        _texte(context, running.step.name, etapeSize, maxLines: 2),
        Semantics(
          label: fini
              ? 'Dépassé de ${minuteurParle(reading.overrun)}'
              : '${minuteurParle(reading.remaining)} restantes',
          excludeSemantics: true,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              fini
                  ? formatMinuteur(reading.overrun, depassement: true)
                  : formatMinuteur(reading.remaining),
              key: const ValueKey('minuteur'),
              style: TextStyle(
                fontSize: timerSize,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: fini ? scheme.onTertiaryContainer : scheme.onSurface,
              ),
            ),
          ),
        ),
        Text(
          !fini
              ? 'restantes sur ${formatDuree(running.duree)}'
              : reading.overrun < const Duration(minutes: 1)
              ? 'Dépassé · prévu ${formatDuree(running.duree)}'
              : 'Dépassé de ${formatDuree(reading.overrun)} · prévu ${formatDuree(running.duree)}',
          style: TextStyle(fontSize: ensuiteSize),
        ),
        if (temp != null)
          Text(
            mesure == null
                ? 'Visée ${formatCelsius(temp)}'
                : 'Visée ${formatCelsius(temp)} · mesurée '
                      '${formatCelsius(mesure.value!)} à ${formatHeure(mesure.measuredAt)}',
            style: TextStyle(fontSize: ensuiteSize),
          ),
        if (suivante != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Ensuite : ${[suivante.step.name, if (suivante.step.tempC != null) formatCelsius(suivante.step.tempC!), 'vers ${formatHeure(suivante.schedule.expectedStart)}'].join(' · ')}',
              style: TextStyle(fontSize: ensuiteSize),
            ),
          ),
        if (ligneFin != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(ligneFin),
          ),
      ],
    );
    if (!depasse) return content;
    return Material(
      color: scheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.all(12), child: content),
    );
  }
}

class _BarreActions extends StatelessWidget {
  const _BarreActions({
    required this.plan,
    required this.role,
    required this.onMesure,
    required this.onTerminerEtape,
    required this.onCommencer,
    required this.onTerminerBrassage,
    required this.onTerminerJournee,
    required this.onEmbouteiller,
    required this.onRetour,
    required this.height,
  });

  final PlanDuJour? plan;

  /// Rôle de la journée 2 ou suivante ; `null` pour le brassage.
  final RoleJournee? role;
  final void Function(LigneJour?) onMesure;
  final void Function(LigneJour) onTerminerEtape;
  final void Function(LigneJour, PlanDuJour) onCommencer;
  final VoidCallback onTerminerBrassage;
  final VoidCallback onTerminerJournee;
  final VoidCallback onEmbouteiller;
  final VoidCallback onRetour;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = plan;
    final running = p?.enCours;
    final next = p?.prochaine;
    final String? principal;
    final VoidCallback? action;
    if (running != null && role == RoleJournee.autre && next == null) {
      // Dernière étape commencée d'une journée « autre » : la terminer termine
      // la journée (ADR-010).
      principal = TextesJournee.terminer;
      action = onTerminerJournee;
    } else if (running != null) {
      principal = 'Terminer l\'étape';
      action = () => onTerminerEtape(running);
    } else if (next != null) {
      principal = next.step.durationMin == 0 ? 'Fait' : 'Commencer l\'étape';
      action = () => onCommencer(next, p!);
    } else if (p != null && (p.termine || role == RoleJournee.embouteillage)) {
      (principal, action) = switch (role) {
        null => ('Terminer le brassage', onTerminerBrassage),
        RoleJournee.embouteillage => (
          TextesJournee.embouteiller,
          onEmbouteiller,
        ),
        _ => (TextesJournee.revenir, onRetour),
      };
    } else {
      principal = null;
      action = null;
    }
    final textStyle = TextStyle(fontSize: 22, color: scheme.onPrimary);
    // Hauteur minimale, pas fixe : à 200 %, le libellé garde sa place.
    final taille = Size.fromHeight(height);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: taille,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () => onMesure(running),
              icon: const Icon(Icons.edit_outlined, size: 24),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Mesure',
                  maxLines: 1,
                  style: TextStyle(fontSize: 22),
                ),
              ),
            ),
          ),
          if (principal != null) ...[
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: taille),
                onPressed: action,
                child: Text(
                  principal,
                  textAlign: TextAlign.center,
                  style: textStyle,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
