import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/app_update_service.dart';
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
  bool lancee = false;
  bool proposee = false;
  MiseAJourDisponible? disponible;
}

final etatMiseAJourProvider = Provider<EtatMiseAJour>((ref) => EtatMiseAJour());

/// Vérifie une fois par lancement, après la connexion d'un membre (la coquille
/// n'est montrée qu'à un membre), si une nouvelle version de l'APK existe, et
/// propose la fenêtre « Nouvelle version ». Si la route courante est l'écran
/// du jour ou une journée, la fenêtre attend qu'on en sorte.
class VerificationMiseAJour extends ConsumerStatefulWidget {
  const VerificationMiseAJour({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<VerificationMiseAJour> createState() =>
      _VerificationMiseAJourState();
}

class _VerificationMiseAJourState extends ConsumerState<VerificationMiseAJour> {
  GoRouterDelegate? _delegue;

  @override
  void initState() {
    super.initState();
    final etat = ref.read(etatMiseAJourProvider);
    if (!etat.lancee) {
      etat.lancee = true;
      unawaited(_verifier(etat));
    }
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

  /// La fenêtre s'ouvre après l'image en cours, une fois la navigation finie.
  void _planifier() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _proposer());

  @override
  void dispose() {
    _delegue?.removeListener(_planifier);
    super.dispose();
  }

  Future<void> _verifier(EtatMiseAJour etat) async {
    final disponible = await ref.read(appUpdateServiceProvider).verifier();
    if (disponible == null) return;
    etat.disponible = disponible;
    if (mounted) _proposer();
  }

  /// Chemin courant, y compris une page ouverte par `push`.
  String? _cheminCourant() {
    final routeur = GoRouter.maybeOf(context);
    if (routeur == null) return null;
    return routeur.state.uri.path;
  }

  void _proposer() {
    if (!mounted) return;
    final etat = ref.read(etatMiseAJourProvider);
    final disponible = etat.disponible;
    if (disponible == null || etat.proposee) return;
    final chemin = _cheminCourant();
    if (chemin == null || routeSansMiseAJour(chemin)) return;
    etat.proposee = true;
    unawaited(
      showAppUpdateDialog(
        context,
        miseAJour: disponible,
        service: ref.read(appUpdateServiceProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
