import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../domain/ticket.dart';
import 'admin_ticket_screen.dart';
import 'bandeau_tickets_admin.dart';
import 'section_lancements.dart';
import 'section_livraison.dart';
import 'ticket_statut.dart';
import 'tickets_providers.dart';

/// Filtre de la liste d'Admin › Tickets. Le choix n'est pas stocké.
enum FiltreTickets { aTraiter, tous, bloques }

/// Nom de l'auteur d'un ticket pour l'administrateur : le nom déclaré dans
/// `members/{email}`, sinon l'adresse. Jamais publié sur l'Issue.
String auteurTicket(Ticket ticket, Map<String, String> names) {
  final email = ticket.authorEmail;
  if (email == null) return 'Auteur inconnu';
  return names[email] ?? email;
}

/// Pastilles propres à l'administrateur, après celle du statut : décision en
/// cours, Issue disparue, envoi en retard.
List<Widget> pastillesAdmin(Ticket ticket, DateTime now) => [
  if (ticket.decisionInProgress(now))
    const Etiquette(
      label: 'Décision en cours',
      icon: Icons.hourglass_top,
      ton: TonEtiquette.neutre,
    ),
  if (ticket.issueMissingSince != null)
    const Etiquette(
      label: 'Issue disparue',
      icon: Icons.link_off,
      ton: TonEtiquette.erreur,
    ),
  if (ticket.isLate(now))
    const Etiquette(
      label: 'En retard',
      icon: Icons.schedule,
      ton: TonEtiquette.erreur,
    ),
];

/// Filtre choisi dans Admin › Tickets, gardé en mémoire tant que la liste ou
/// une fiche est ouverte (jamais stocké). [ajuste] : le passage unique sur
/// « Tous » quand rien n'est à traiter est fait.
class FiltreTicketsNotifier
    extends Notifier<({FiltreTickets filtre, bool ajuste})> {
  @override
  ({FiltreTickets filtre, bool ajuste}) build() =>
      (filtre: FiltreTickets.aTraiter, ajuste: false);

  void choisir(FiltreTickets filtre) => state = (filtre: filtre, ajuste: true);

  /// À la première liste lue : « Tous » s'il n'y a rien à traiter.
  void ajuster({required bool rienATraiter}) {
    if (state.ajuste) return;
    state = (
      filtre: rienATraiter ? FiltreTickets.tous : state.filtre,
      ajuste: true,
    );
  }
}

final filtreTicketsProvider =
    NotifierProvider.autoDispose<
      FiltreTicketsNotifier,
      ({FiltreTickets filtre, bool ajuste})
    >(FiltreTicketsNotifier.new);

/// Liste et fiche côte à côte dans Admin › Tickets : fenêtre assez large
/// pour le rail étendu et [kExpandedMinWidth] de contenu.
bool adminTicketsCoteACote(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kTicketsAdminCoteACoteMinWidth;

/// Clé de la page de `/admin/tickets` et `/admin/tickets/:id`. En large, les
/// deux routes partagent une clé : choisir un ticket met la page à jour sans
/// transition, la liste garde son défilement. Une page empilée par `push`
/// (téléphone) garde sa clé unique, qui ne commence pas par « / ».
LocalKey cleDePageTicketsAdmin(BuildContext context, GoRouterState state) =>
    adminTicketsCoteACote(context) && state.pageKey.value.startsWith('/')
    ? const ValueKey<String>('admin-tickets')
    : state.pageKey;

/// Admin › Tickets des membres : bandeau, filtres, liste du plus récent au
/// plus ancien. Réservé au rôle `admin` (routeur et règles).
///
/// [adminTicketsCoteACote] : la liste à gauche ([kListeTicketsAdminWidth]) et
/// la fiche [selectedId] à droite, ouverte par `go`. En dessous : la liste seule, ou la fiche seule si [selectedId] est
/// donné, ouverte par `push`.
class AdminTicketsScreen extends ConsumerWidget {
  const AdminTicketsScreen({super.key, this.selectedId});

  final String? selectedId;

  static const titre = 'Tickets des membres';
  static const loadError = 'Impossible de lire les tickets.';
  static const emptyMessage =
      'Aucun ticket pour l\'instant. Les membres n\'ont encore rien signalé.';
  static const nothingToProcess =
      'Rien à traiter. Tous les tickets ont reçu une décision.';
  static const nothingBlocked = 'Aucun ticket bloqué.';
  static const showAll = 'Afficher tous les tickets';
  static const noSelection = 'Choisissez un ticket pour voir son suivi.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Builder(
      builder: (context) {
        final wide = adminTicketsCoteACote(context);
        final selected = selectedId;
        if (!wide && selected != null) return AdminTicketScreen(id: selected);
        // Material propre : le fond de la ligne choisie et l'encre de l'appui
        // se peignent sur lui, pas sous le fond de la transition de page.
        final liste = Material(
          type: MaterialType.transparency,
          child: _PanneauListe(selectedId: selected, wide: wide),
        );
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BandeauTicketsAdmin(),
              Expanded(child: liste),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BandeauTicketsAdmin(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: kListeTicketsAdminWidth, child: liste),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: selected == null
                        ? const EtatVide(
                            icon: Icons.confirmation_number_outlined,
                            message: noSelection,
                          )
                        : AdminTicketScreen(
                            key: ValueKey(selected),
                            id: selected,
                            avecBandeau: false,
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Filtres et liste ; [wide] : la fiche s'ouvre à côté (`go`), sinon par
/// `push`.
class _PanneauListe extends ConsumerWidget {
  const _PanneauListe({required this.selectedId, required this.wide});

  final String? selectedId;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminTicketsProvider);
    final list = async.value;
    final now = ref.watch(horlogeProvider)();
    final filtre = ref.watch(filtreTicketsProvider).filtre;
    final notifier = ref.read(filtreTicketsProvider.notifier);
    final valides = list?.valides ?? const <Ticket>[];
    // « À traiter » de la liste : statut, plus les tickets En cours dont la
    // PR est prête (décision 7 du 2026-11-14) ; le compteur du menu reste sur
    // le statut seul.
    final pretes = ref.watch(ticketsPrPreteProvider);
    final prPretes = pretes.ids;
    final toProcess = valides
        .where((t) => t.toProcess || prPretes.contains(t.id))
        .length;
    final blocked = valides.where((t) => t.isBlocked(now)).length;
    // Le premier filtre attend l'état des PR des tickets En cours : un ticket
    // dont la PR est prête est à traiter.
    if (list != null && pretes.lu && !ref.read(filtreTicketsProvider).ajuste) {
      // Après la construction : un fournisseur ne change pas pendant un
      // build.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => notifier.ajuster(rienATraiter: toProcess == 0),
      );
    }
    void retry() => ref.invalidate(adminTicketsProvider);
    void open(String id) {
      final location = AppRoutes.adminTicket(id);
      if (wide) {
        context.go(location);
      } else {
        unawaited(context.push(location));
      }
    }

    final Widget body;
    if (list == null) {
      body = async.hasError
          ? EtatErreur(
              message: AdminTicketsScreen.loadError,
              retrying: async.isLoading,
              retryingLabel: 'Lecture en cours',
              onRetry: retry,
            )
          : const EtatChargement(label: 'Chargement des tickets');
    } else {
      body = _Liste(
        list: list,
        prPretes: prPretes,
        filtre: filtre,
        now: now,
        selectedId: selectedId,
        stale: async.hasError,
        retrying: async.isLoading,
        onRetry: retry,
        onOpen: open,
        onShowAll: () => notifier.choisir(FiltreTickets.tous),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CompteurLancements(),
        _Filtres(
          filtre: filtre,
          toProcess: list == null ? null : toProcess,
          blocked: list == null ? null : blocked,
          // Dans le panneau de gauche, les puces défilent comme au téléphone.
          scroll: wide || MediaQuery.sizeOf(context).width < kCompactMaxWidth,
          onSelected: notifier.choisir,
        ),
        const Divider(height: 1),
        Expanded(child: body),
      ],
    );
  }
}

class _Filtres extends StatelessWidget {
  const _Filtres({
    required this.filtre,
    required this.toProcess,
    required this.blocked,
    required this.scroll,
    required this.onSelected,
  });

  final FiltreTickets filtre;

  /// Défilement horizontal (téléphone, panneau de gauche), sinon `Wrap`.
  final bool scroll;

  /// `null` tant que la liste n'est pas lue : pas de nombre.
  final int? toProcess;
  final int? blocked;
  final ValueChanged<FiltreTickets> onSelected;

  @override
  Widget build(BuildContext context) {
    String avecNombre(String label, int? n) =>
        n == null ? label : '$label ($n)';
    final chips = [
      for (final (f, label) in [
        (FiltreTickets.aTraiter, avecNombre('À traiter', toProcess)),
        (FiltreTickets.tous, 'Tous'),
        (FiltreTickets.bloques, avecNombre('Bloqués', blocked)),
      ])
        ChoiceChip(
          label: Text(label),
          selected: filtre == f,
          onSelected: (_) => onSelected(f),
        ),
    ];
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 8);
    if (scroll) {
      // Défilement horizontal : à 200 %, les puces ne tiennent pas sur une
      // ligne.
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (final (i, c) in chips.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              c,
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: padding,
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }
}

class _Liste extends ConsumerWidget {
  const _Liste({
    required this.list,
    required this.prPretes,
    required this.filtre,
    required this.now,
    required this.selectedId,
    required this.stale,
    required this.retrying,
    required this.onRetry,
    required this.onOpen,
    required this.onShowAll,
  });

  final ListeLue<Ticket> list;

  /// Tickets En cours dont la PR est prête : sous « À traiter ».
  final Set<String> prPretes;
  final FiltreTickets filtre;
  final DateTime now;
  final String? selectedId;
  final ValueChanged<String> onOpen;
  final bool stale;
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(memberNamesProvider);
    final tickets = [
      for (final t in list.valides)
        if (switch (filtre) {
          FiltreTickets.aTraiter => t.toProcess || prPretes.contains(t.id),
          FiltreTickets.tous => true,
          FiltreTickets.bloques => t.isBlocked(now),
        })
          t,
    ]..sort(compareTicketsRecentFirst);
    // Un ticket illisible n'a ni statut ni date : il n'apparaît que sous
    // « Tous ».
    final invalid = filtre == FiltreTickets.tous
        ? list.documents.whereType<DocumentInvalide<Ticket>>().toList()
        : const <DocumentInvalide<Ticket>>[];
    final banner = stale
        ? BandeauListePerimee(retrying: retrying, onRetry: onRetry)
        : null;

    if (tickets.isEmpty && invalid.isEmpty) {
      final showAll = FilledButton(
        onPressed: onShowAll,
        child: const Text(AdminTicketsScreen.showAll),
      );
      final empty = list.documents.isEmpty
          ? const EtatVide(
              icon: Icons.confirmation_number_outlined,
              message: AdminTicketsScreen.emptyMessage,
            )
          : switch (filtre) {
              FiltreTickets.aTraiter => EtatVide(
                icon: Icons.inbox_outlined,
                message: AdminTicketsScreen.nothingToProcess,
                action: showAll,
              ),
              FiltreTickets.bloques => EtatVide(
                icon: Icons.check_circle_outline,
                message: AdminTicketsScreen.nothingBlocked,
                action: showAll,
              ),
              FiltreTickets.tous => const EtatVide(
                icon: Icons.confirmation_number_outlined,
                message: AdminTicketsScreen.emptyMessage,
              ),
            };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?banner,
          Expanded(child: empty),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        ?banner,
        for (final t in tickets)
          _Ligne(
            ticket: t,
            names: names,
            now: now,
            selected: t.id == selectedId,
            onTap: () => onOpen(t.id),
          ),
        for (final d in invalid)
          ListTile(
            leading: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('Ticket illisible'),
            subtitle: const Text('Mettez l\'application à jour.'),
            selected: d.id == selectedId,
            selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
            selectedColor: Theme.of(context).colorScheme.onSecondaryContainer,
            onTap: () => onOpen(d.id),
          ),
      ],
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.ticket,
    required this.names,
    required this.now,
    required this.selected,
    required this.onTap,
  });

  final Ticket ticket;
  final Map<String, String> names;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final created = ticket.createdAt;
    final number = ticket.issueNumber;
    final meta = [
      if (number != null) '#$number',
      auteurTicket(ticket, names),
      if (created != null) formatDateChiffres(created),
    ].join(' · ');
    return ListTile(
      leading: Semantics(
        label: ticket.type.label,
        child: ExcludeSemantics(
          child: Icon(
            ticketTypeIcon(ticket.type),
            color: selected
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(ticket.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(meta),
            EtiquetteStatut(ticket: ticket),
            ...pastillesAdmin(ticket, now),
            PastilleLancement(ticket: ticket),
            PastilleLivraison(ticket: ticket),
          ],
        ),
      ),
      selected: selected,
      // Ligne choisie : même marquage que « Mes tickets ».
      selectedTileColor: scheme.secondaryContainer,
      selectedColor: scheme.onSecondaryContainer,
      onTap: onTap,
    );
  }
}
