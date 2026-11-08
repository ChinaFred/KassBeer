import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../brews/domain/brew.dart';
import '../../brews/presentation/brews_providers.dart';
import 'brew_day_screen.dart';

/// Rouvre l'écran du jour au lancement si le compte a un seul brassin en cours
/// depuis moins de 24 h (D-Q3). Une seule fois par session, depuis l'accueil.
class RepriseBrassage extends ConsumerStatefulWidget {
  const RepriseBrassage({
    super.key,
    required this.location,
    required this.child,
  });

  final String location;
  final Widget child;

  @override
  ConsumerState<RepriseBrassage> createState() => _RepriseBrassageState();
}

class _RepriseBrassageState extends ConsumerState<RepriseBrassage> {
  ProviderSubscription<AsyncValue<ListeLue<Brew>>>? _subscription;

  @override
  void initState() {
    super.initState();
    final traitee = ref.read(repriseTraiteeProvider);
    if (traitee.first) return;
    _subscription = ref.listenManual(
      brewsListProvider,
      (_, next) => _verifier(next),
      fireImmediately: true,
    );
  }

  void _verifier(AsyncValue<ListeLue<Brew>> async) {
    final list = async.value;
    final traitee = ref.read(repriseTraiteeProvider);
    if (list == null || traitee.first) return;
    traitee.first = true;
    _subscription?.close();
    _subscription = null;
    if (widget.location != AppRoutes.home) return;
    final uid = ref.read(grantedAccessProvider)?.user.uid;
    final brew = brassinAReprendre(
      list.valides,
      uid,
      ref.read(horlogeProvider)(),
    );
    if (brew == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      GoRouter.of(
        context,
      ).go(AppRoutes.brewDay(brew.id), extra: kRepriseBrassage);
    });
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
