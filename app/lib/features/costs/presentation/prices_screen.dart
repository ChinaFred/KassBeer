import 'dart:async';

import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/bandeau_hors_ligne.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/menu_compte.dart';
import '../../../core/presentation/zone_capture.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/fee.dart';
import '../domain/price.dart';
import 'costs_providers.dart';
import 'fee_form.dart';
import 'formats_cout.dart';
import 'price_form.dart';

/// « Mes prix » : frais et prix d'achat du brasseur connecté, lus par lui seul
/// (PR1, FR1, P5). Page pleine hors de la coquille, ouverte depuis le menu du
/// compte.
class PricesScreen extends ConsumerWidget {
  const PricesScreen({super.key});

  static const titre = 'Mes prix';
  static const chargement = 'Chargement de vos prix';
  static const lectureImpossible = 'Impossible de lire vos prix.';
  static const horsLigne = 'Prix indisponibles sur cet appareil hors ligne.';
  static const aucunPrix =
      'Aucun prix enregistré. Ajoutez-en un, ou complétez-les depuis une '
      'recette.';
  static const aucunFrais =
      'Aucun frais. Ajoutez l\'eau, l\'électricité, les capsules… pour qu\'ils '
      'comptent dans le coût.';
  static const limiteFrais =
      '$kMaxFees frais au plus. Supprimez-en un pour en ajouter un autre.';
  static const ajouterPrix = 'Ajouter un prix';
  static const ajouterFrais = 'Ajouter un frais';
  static const prixIllisible =
      'Ce prix ne peut pas être lu. Supprimez-le, puis saisissez-le de nouveau.';
  static const fraisIllisible =
      'Ce frais ne peut pas être lu. Supprimez-le, puis saisissez-le de '
      'nouveau.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(grantedAccessProvider);
    final uid = access?.user.uid;
    final offline = access?.offline ?? false;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < kCompactMaxWidth;

    final AsyncValue<ListeLue<Price>>? pricesAsync = uid == null
        ? null
        : ref.watch(pricesProvider(uid));
    final AsyncValue<ListeLue<Fee>>? feesAsync = uid == null
        ? null
        : ref.watch(feesProvider(uid));
    final prices = pricesAsync?.value;
    final fees = feesAsync?.value;
    final failed =
        (prices == null && (pricesAsync?.hasError ?? false)) ||
        (fees == null && (feesAsync?.hasError ?? false));
    final sansCache =
        prices != null &&
        fees != null &&
        prices.fromCache &&
        prices.documents.isEmpty &&
        fees.fromCache &&
        fees.documents.isEmpty;
    final pret = uid != null && prices != null && fees != null && !failed;

    void nouveauPrix() => unawaited(
      ouvrirFormulairePrix(
        context,
        uid: uid!,
        mesPrix: prices!.valides,
        mode: ModePrix.nouveau,
      ),
    );

    final Widget body;
    if (failed) {
      body = EtatErreur(
        message: lectureImpossible,
        retrying:
            (pricesAsync?.isLoading ?? false) ||
            (feesAsync?.isLoading ?? false),
        retryingLabel: 'Lecture en cours',
        onRetry: () {
          ref.invalidate(pricesProvider(uid!));
          ref.invalidate(feesProvider(uid));
        },
      );
    } else if (!pret) {
      body = const EtatChargement(label: chargement);
    } else if (sansCache) {
      body = const EtatVide(icon: Icons.cloud_off, message: horsLigne);
    } else {
      body = _Contenu(
        uid: uid,
        prices: prices,
        fees: fees,
        compact: compact,
        ouvert: width >= kExpandedMinWidth,
        onAjouterPrix: nouveauPrix,
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
        title: const Text(titre),
        actions: const [MenuCompte(), SizedBox(width: 8)],
      ),
      body: ZoneCapture(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (offline) const BandeauHorsLigne(),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: compact && pret && !sansCache
          ? FloatingActionButton.extended(
              onPressed: nouveauPrix,
              icon: const Icon(Icons.add),
              label: const Text(ajouterPrix),
            )
          : null,
    );
  }
}

class _Contenu extends ConsumerWidget {
  const _Contenu({
    required this.uid,
    required this.prices,
    required this.fees,
    required this.compact,
    required this.ouvert,
    required this.onAjouterPrix,
  });

  final String uid;
  final ListeLue<Price> prices;
  final ListeLue<Fee> fees;
  final bool compact;
  final bool ouvert;
  final VoidCallback onAjouterPrix;

  int _parNom(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

  /// Supprime un document illisible après confirmation : il ne peut pas être
  /// relu, donc pas rétabli par « Annuler ».
  Future<void> _supprimerIllisible(
    BuildContext context,
    WidgetRef ref, {
    required bool frais,
    required String id,
  }) async {
    final repo = ref.read(costsRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    // ticket: aucun (confirmation)
    final confirme = await confirmerAction(
      context,
      titre: frais
          ? 'Supprimer le frais illisible ?'
          : 'Supprimer le prix illisible ?',
      paragraphes: const [
        'Il ne peut pas être relu : la suppression ne pourra pas être annulée.',
      ],
      libelle: 'Supprimer',
      destructive: true,
    );
    if (!confirme) return;
    suivreEcriture(
      messenger: messenger,
      written: frais
          ? repo.deleteFee(uid: uid, id: id)
          : repo.deletePrice(uid: uid, key: id),
      succes: frais ? 'Frais illisible supprimé.' : 'Prix illisible supprimé.',
      refus: 'La suppression a échoué.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mesFrais = fees.valides..sort((a, b) => _parNom(a.name, b.name));
    final fraisIllisibles = fees.documents.whereType<DocumentInvalide<Fee>>();
    final mesPrix = prices.valides;
    final parNature = <IngredientNature, List<Price>>{};
    for (final p in mesPrix) {
      parNature.putIfAbsent(p.nature, () => []).add(p);
    }
    final prixIllisibles = prices.documents
        .whereType<DocumentInvalide<Price>>();

    Widget illisible({required bool frais, required String id}) => ListTile(
      leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
      title: Text(frais ? 'Frais illisible' : 'Prix illisible'),
      subtitle: Text(
        frais ? PricesScreen.fraisIllisible : PricesScreen.prixIllisible,
      ),
      trailing: TextButton(
        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        onPressed: () =>
            unawaited(_supprimerIllisible(context, ref, frais: frais, id: id)),
        child: Text(
          'Supprimer',
          semanticsLabel: frais
              ? 'Supprimer le frais illisible'
              : 'Supprimer le prix illisible',
        ),
      ),
    );

    // Une clé hors du format des règles est lue comme un prix illisible
    // (`Price.fromFirestore`) : chaque prix lisible a une nature.
    List<Widget> section(IngredientNature nature, List<Price> items) {
      items.sort((a, b) => _parNom(a.name, b.name));
      return [
        SectionRepliable(
          titre: libelleNaturePluriel(nature),
          storageKey: 'prix-${nature.prefix}',
          resume: '${items.length} prix',
          ouvert: ouvert,
          children: [
            for (final p in items)
              LignePrix(
                price: p,
                onTap: () => unawaited(
                  ouvrirFormulairePrix(
                    context,
                    uid: uid,
                    mesPrix: mesPrix,
                    mode: ModePrix.modification,
                    initial: p,
                  ),
                ),
                trailing: p.hasPendingWrites
                    ? const Etiquette(label: 'En attente du réseau')
                    : null,
              ),
          ],
        ),
      ];
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, compact ? 96 : 24),
      children: [
        TitreSection(
          'Mes frais',
          trailing: fees.documents.isEmpty
              ? null
              : '${fees.documents.length} frais',
        ),
        if (fees.documents.isEmpty) const TexteAbsent(PricesScreen.aucunFrais),
        for (final f in mesFrais)
          _LigneFrais(
            fee: f,
            onTap: () =>
                unawaited(ouvrirFormulaireFrais(context, uid: uid, initial: f)),
          ),
        for (final d in fraisIllisibles) illisible(frais: true, id: d.id),
        const SizedBox(height: 8),
        if (fees.documents.length >= kMaxFees)
          const Text(PricesScreen.limiteFrais)
        else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  unawaited(ouvrirFormulaireFrais(context, uid: uid)),
              icon: const Icon(Icons.add),
              label: const Text(PricesScreen.ajouterFrais),
            ),
          ),
        const TitreSection('Ingrédients'),
        if (!compact)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: onAjouterPrix,
                icon: const Icon(Icons.add),
                label: const Text(PricesScreen.ajouterPrix),
              ),
            ),
          ),
        if (prices.documents.isEmpty)
          const EtatVide(
            icon: Icons.sell_outlined,
            message: PricesScreen.aucunPrix,
          ),
        for (final nature in IngredientNature.values)
          if (parNature[nature] case final items?) ...section(nature, items),
        for (final d in prixIllisibles) illisible(frais: false, id: d.id),
      ],
    );
  }
}

/// Ligne d'un frais : « Électricité · 2,00 € par brassin ».
class _LigneFrais extends StatelessWidget {
  const _LigneFrais({required this.fee, required this.onTap});

  final Fee fee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final texte = parties([
      fee.name,
      '${formatEurosSaisis(fee.amountEur)} ${libelleBase(fee.basis)}',
    ]);
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  texte.texte,
                  semanticsLabel: texte.parle,
                  style: theme.textTheme.bodyLarge,
                ),
                if (fee.hasPendingWrites) ...[
                  const SizedBox(height: 8),
                  const Etiquette(label: 'En attente du réseau'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
