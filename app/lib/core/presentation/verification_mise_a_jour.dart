import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/app_update_service.dart';
import '../../features/brews/presentation/brews_providers.dart';
import 'app_update_dialog.dart';

/// Écran du jour (`/brassins/:id/jour`) et journée du déroulé
/// (`/brassins/:id/jour/:journee`) : aucune fenêtre de mise à jour (ADR-012,
/// arbitrage 5 ; P2). La préparation d'une journée (`…/preparer`) n'en est pas.
final _routesSansMiseAJour = RegExp(r'^/brassins/[^/]+/jour(/[^/]+)?$');

/// Vrai si [chemin] est l'écran du jour ou une journée du déroulé.
bool routeSansMiseAJour(String chemin) => _routesSansMiseAJour.hasMatch(chemin);

/// État de la vérification pour ce lancement de l'application : rien n'est
/// mémorisé sur l'appareil (« Plus tard » la fait revenir au lancement
/// suivant, arbitrage 3).
class EtatMiseAJour {
  /// Lecture du manifeste partie (une fois par lancement).
  bool lancee = false;

  /// Fenêtre ouverte ; repasse à faux si elle disparaît sans choix.
  bool proposee = false;

  /// Le brasseur a choisi (« Plus tard », installateur ouvert).
  bool choisie = false;

  MiseAJourDisponible? disponible;
}

final etatMiseAJourProvider = Provider<EtatMiseAJour>((ref) => EtatMiseAJour());

/// Vérifie une fois par lancement, après la connexion d'un membre (la coquille
/// n'est montrée qu'à un membre), si une nouvelle version de l'APK existe, et
/// propose la fenêtre « Nouvelle version ».
///
/// Ni la lecture du manifeste ni la fenêtre n'ont lieu sur l'écran du jour ou
/// une journée (P2, P51). La lecture attend que la reprise du brassage
/// (`RepriseBrassage`) ait décidé, puis une image de plus : si la reprise
/// envoie vers l'écran du jour, la lecture attend le retour.
class VerificationMiseAJour extends ConsumerStatefulWidget {
  const VerificationMiseAJour({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<VerificationMiseAJour> createState() =>
      _VerificationMiseAJourState();
}

class _VerificationMiseAJourState extends ConsumerState<VerificationMiseAJour> {
  GoRouterDelegate? _delegue;
  ProviderSubscription<AsyncValue<Object?>>? _brassins;
  bool _attente = false;

  /// Liste des brassins en panne : la reprise ne décidera pas, la lecture du
  /// manifeste n'attend plus.
  bool _repriseImpossible = false;

  @override
  void initState() {
    super.initState();
    final etat = ref.read(etatMiseAJourProvider);
    if (etat.lancee || ref.read(repriseTraiteeProvider).first) return;
    // La reprise décide à la lecture de la liste des brassins : chaque
    // nouvelle liste relance l'essai. L'écoute se ferme dès que la lecture
    // du manifeste est partie.
    _brassins = ref.listenManual<AsyncValue<Object?>>(brewsListProvider, (
      _,
      suivante,
    ) {
      if (suivante.hasError) _repriseImpossible = true;
      _planifier();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final delegue = GoRouter.maybeOf(context)?.routerDelegate;
    if (delegue == _delegue) return;
    _delegue?.removeListener(_planifier);
    _delegue = delegue?..addListener(_planifier);
    _planifier();
  }

  /// Après l'image en cours, une fois la navigation finie.
  void _planifier() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_essayerVerifier());
      _proposer();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _delegue?.removeListener(_planifier);
    _brassins?.close();
    super.dispose();
  }

  /// Chemin courant, y compris une page ouverte par `push`.
  String? _cheminCourant() {
    final routeur = GoRouter.maybeOf(context);
    if (routeur == null) return null;
    return routeur.state.uri.path;
  }

  bool get _horsEcranDuJour {
    final chemin = _cheminCourant();
    return chemin != null && !routeSansMiseAJour(chemin);
  }

  Future<void> _essayerVerifier() async {
    final etat = ref.read(etatMiseAJourProvider);
    if (!mounted || etat.lancee || _attente) return;
    if (!ref.read(repriseTraiteeProvider).first && !_repriseImpossible) return;
    // La reprise navigue dans le rappel d'après image où elle a décidé : la
    // route se relit une image plus tard.
    _attente = true;
    await WidgetsBinding.instance.endOfFrame;
    _attente = false;
    if (!mounted || etat.lancee || !_horsEcranDuJour) return;
    etat.lancee = true;
    _brassins?.close();
    _brassins = null;
    final disponible = await ref.read(appUpdateServiceProvider).verifier();
    if (disponible == null) return;
    etat.disponible = disponible;
    if (mounted) _proposer();
  }

  void _proposer() {
    if (!mounted) return;
    final etat = ref.read(etatMiseAJourProvider);
    final disponible = etat.disponible;
    if (disponible == null || etat.proposee || etat.choisie) return;
    if (!_horsEcranDuJour) return;
    etat.proposee = true;
    unawaited(_ouvrir(etat, disponible));
  }

  Future<void> _ouvrir(EtatMiseAJour etat, MiseAJourDisponible dispo) async {
    final service = ref.read(appUpdateServiceProvider);
    final choix = await showAppUpdateDialog(
      context,
      miseAJour: dispo,
      service: service,
    );
    if (choix == true) {
      etat.choisie = true;
      return;
    }
    // Fenêtre retirée sans choix (page remplacée sous elle) : elle reviendra
    // au prochain écran permis de ce lancement.
    etat.proposee = false;
    if (mounted) _planifier();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
