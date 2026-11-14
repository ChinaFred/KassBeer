import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/access_providers.dart';
import '../../features/auth/presentation/sign_out.dart';
import '../../features/tickets/domain/ticket_screens.dart';
import '../../features/tickets/presentation/capture_ticket.dart';
import '../../features/tickets/presentation/ticket_form_screen.dart';
import '../../features/tickets/presentation/tickets_providers.dart';
import '../providers.dart';
import '../router/routes.dart';
import 'breakpoints.dart';

/// Texte d'une pastille : « 99+ » au-delà de 99.
String textePastille(int count) => count > 99 ? '99+' : '$count';

/// Infobulle de l'avatar : « Mon compte », suivie des suivis à lire et, pour
/// l'administrateur, des tickets à traiter.
String infobulleCompte({required int unread, required int toProcess}) => [
  'Mon compte',
  if (unread == 1) '1 suivi de ticket à lire',
  if (unread > 1) '$unread suivis de ticket à lire',
  if (toProcess == 1) '1 ticket à traiter',
  if (toProcess > 1) '$toProcess tickets à traiter',
].join(', ');

/// Entrée du menu du compte masquée sur l'écran qu'elle ouvre.
enum EntreeCompte {
  prix,
  processus,
  preferences,
  signaler,
  tickets,
  ticketsATraiter,
  nouveautes,
  sources,
}

/// Modèle de route (`fullPath`) → entrée qui mène à cet écran. Sur `/processus/:id`
/// ou `/tickets/:id`, « Mes processus » et « Mes tickets » restent.
const Map<String, EntreeCompte> kEntreeDeLEcran = {
  AppRoutes.prices: EntreeCompte.prix,
  AppRoutes.processes: EntreeCompte.processus,
  AppRoutes.preferences: EntreeCompte.preferences,
  AppRoutes.newTicket: EntreeCompte.signaler,
  AppRoutes.tickets: EntreeCompte.tickets,
  AppRoutes.adminTickets: EntreeCompte.ticketsATraiter,
  AppRoutes.news: EntreeCompte.nouveautes,
  AppRoutes.dataSources: EntreeCompte.sources,
};

/// Avatar et menu du compte, dans la barre du haut de la coquille et des pages
/// pleines : nom, e-mail, version, Mes prix, Mes processus, Préférences,
/// Signaler ou proposer, Mes tickets, Tickets à traiter (admin), Nouveautés,
/// Sources des données, déconnexion. La pastille compte les suivis de ticket à
/// lire et, pour l'administrateur, les tickets à traiter. Rien sans accès
/// accordé. L'entrée qui mène à l'écran courant est masquée.
///
/// Les entrées s'ouvrent par `push`, sauf « Tickets à traiter » (`go`) et la
/// déconnexion : avant elles, et avant « Mes processus », [avantDeQuitter] est
/// appelé ; il rend `false` pour rester (travail non enregistré).
class MenuCompte extends ConsumerWidget {
  const MenuCompte({
    super.key,
    this.photo = true,
    this.avantDeQuitter,
    this.avantDeDeconnecter,
  });

  /// Faux : l'initiale seule, aucune image chargée par le réseau (écran du
  /// jour, P2).
  final bool photo;

  /// Appelé avant « Tickets à traiter », « Mes processus » et « Se
  /// déconnecter » ; `false` annule l'action.
  final Future<bool> Function()? avantDeQuitter;

  /// Appelé avant « Se déconnecter », après [avantDeQuitter] ; `false` annule
  /// (saisies du jour de brassage en attente du réseau).
  final Future<bool> Function()? avantDeDeconnecter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accessStateProvider);
    if (access is! AccessGranted) return const SizedBox.shrink();
    final user = access.user;
    final isAdmin = access.member.isAdmin;
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider);
    final name = user.displayName?.trim();
    final initial =
        (name != null && name.isNotEmpty ? name : (user.email ?? '?'))
            .characters
            .first
            .toUpperCase();
    final url = photo ? user.photoUrl : null;
    final unread = ref.watch(unreadTicketsCountProvider);
    final toProcess = ref.watch(ticketsToProcessCountProvider);
    final total = unread + toProcess;
    // État de la page qui porte ce menu, reconstruit à chaque changement de
    // route (la coquille garde la même instance de menu).
    final fullPath = GoRouterState.of(context).fullPath;
    final masquee = kEntreeDeLEcran[fullPath];
    bool visible(EntreeCompte e) => e != masquee;

    Future<bool> peutQuitter() async {
      final avant = avantDeQuitter;
      return avant == null || await avant();
    }

    Future<void> ouvrirProcessus() async {
      if (!await peutQuitter() || !context.mounted) return;
      unawaited(context.push(AppRoutes.processes));
    }

    Future<void> ouvrirTicketsATraiter() async {
      if (!await peutQuitter() || !context.mounted) return;
      context.go(AppRoutes.adminTickets);
    }

    // Capture du contenu de la page, prise avant la navigation : le menu
    // ouvert, la barre du haut et la barre de navigation n'y figurent pas
    // (ADR-008, T6). Elle attend le formulaire en mémoire.
    Future<void> signaler() async {
      final png = await ref.read(capturerEcranProvider)(context);
      if (!context.mounted) return;
      ref
          .read(captureEnAttenteProvider)
          .poser(
            png == null
                ? null
                : CaptureEcran(png: png, ecran: ticketScreenValue(fullPath)),
          );
      unawaited(context.push(ticketFormLocation(fullPath)));
    }

    Future<void> deconnecter() async {
      if (!await peutQuitter() || !context.mounted) return;
      final avant = avantDeDeconnecter;
      if (avant != null && !await avant()) return;
      if (!context.mounted) return;
      await signOutFrom(context, ref);
    }

    // ticket: <coquille>/menu/compte, <hors-coquille>/menu/compte
    return MenuAnchor(
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kAccountMenuMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name != null && name.isNotEmpty)
                  Text(name, style: theme.textTheme.titleMedium),
                if (user.email != null)
                  Text(user.email!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text(
                  version == null ? 'Version indisponible' : 'Version $version',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(),
        if (visible(EntreeCompte.prix))
          MenuItemButton(
            leadingIcon: const Icon(Icons.sell_outlined),
            onPressed: () => unawaited(context.push(AppRoutes.prices)),
            child: const Text('Mes prix'),
          ),
        if (visible(EntreeCompte.processus))
          MenuItemButton(
            leadingIcon: const Icon(Icons.checklist_outlined),
            onPressed: () => unawaited(ouvrirProcessus()),
            child: const Text('Mes processus'),
          ),
        if (visible(EntreeCompte.preferences))
          MenuItemButton(
            leadingIcon: const Icon(Icons.tune),
            onPressed: () => unawaited(context.push(AppRoutes.preferences)),
            child: const Text('Préférences'),
          ),
        const Divider(),
        if (visible(EntreeCompte.signaler))
          MenuItemButton(
            leadingIcon: const Icon(Icons.feedback_outlined),
            // Le modèle de la route courante (`/recettes/:id`), jamais son
            // adresse : l'écran part sur une Issue publique.
            onPressed: () => unawaited(signaler()),
            child: const Text('Signaler ou proposer'),
          ),
        if (visible(EntreeCompte.tickets))
          MenuItemButton(
            leadingIcon: const Icon(Icons.confirmation_number_outlined),
            trailingIcon: unread == 0
                ? null
                : Badge(label: Text(textePastille(unread))),
            semanticsLabel: unread == 0 ? null : 'Mes tickets, $unread à lire',
            onPressed: () => unawaited(context.push(AppRoutes.tickets)),
            child: const Text('Mes tickets'),
          ),
        if (isAdmin && visible(EntreeCompte.ticketsATraiter))
          MenuItemButton(
            leadingIcon: const Icon(Icons.inbox_outlined),
            trailingIcon: toProcess == 0
                ? null
                : Badge(label: Text(textePastille(toProcess))),
            semanticsLabel: toProcess == 0
                ? null
                : 'Tickets à traiter, $toProcess',
            onPressed: () => unawaited(ouvrirTicketsATraiter()),
            child: const Text('Tickets à traiter'),
          ),
        if (visible(EntreeCompte.nouveautes))
          MenuItemButton(
            leadingIcon: const Icon(Icons.new_releases_outlined),
            onPressed: () => unawaited(context.push(AppRoutes.news)),
            child: const Text('Nouveautés'),
          ),
        if (visible(EntreeCompte.sources))
          MenuItemButton(
            leadingIcon: const Icon(Icons.info_outline),
            onPressed: () => unawaited(context.push(AppRoutes.dataSources)),
            child: const Text('Sources des données'),
          ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: () => unawaited(deconnecter()),
          child: const Text('Se déconnecter'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: infobulleCompte(unread: unread, toProcess: toProcess),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: Badge(
          isLabelVisible: total > 0,
          label: Text(textePastille(total)),
          child: CircleAvatar(
            radius: 16,
            foregroundImage: url == null ? null : NetworkImage(url),
            onForegroundImageError: url == null
                ? null
                : (error, stackTrace) => ref
                      .read(errorReportServiceProvider)
                      .reportError(
                        feature: 'shell.avatar',
                        error: error,
                        stackTrace: stackTrace,
                        // Ni l'URL de la photo (retirée aussi par le service), ni
                        // l'adresse : le type d'erreur et le code HTTP suffisent.
                        context: error is NetworkImageLoadException
                            ? 'photo du compte Google illisible, HTTP ${error.statusCode}'
                            : 'photo du compte Google illisible',
                      ),
            child: ExcludeSemantics(child: Text(initial)),
          ),
        ),
      ),
    );
  }
}
