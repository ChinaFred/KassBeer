import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/formats.dart';
import '../../auth/presentation/access_providers.dart';
import '../data/ai_repository.dart';
import '../domain/comptes_ia.dart';
import '../domain/reglages_ia.dart';
import 'ai_providers.dart';

/// Montant stocké, mis en forme sans recalcul (P60) : « ≈ 0,42 $ », et
/// « < 0,01 $ » sous un centime.
String formatMontantUsd(double usd) => usd > 0 && usd < 0.005
    ? '<${nbsp}0,01$nbsp\$'
    : '≈$nbsp${formatNombre(usd, decimales: 2, fixe: true)}$nbsp\$';

/// « 1 tour », « 12 tours ».
String formatTours(int n) => n <= 1 ? '$n tour' : '$n tours';

/// Texte de la ligne « IA ce mois » pour des comptes lus.
String texteComptesDuMois(ComptesPoste total) {
  if (total.appels == 0) return 'IA ce mois : aucun tour';
  final tours = formatTours(total.appels);
  if (total.montantInconnu) return 'IA ce mois : $tours, montant inconnu';
  final montant = formatMontantUsd(total.montantUsd);
  return total.sansMontant == 0
      ? 'IA ce mois : $tours, $montant'
      : 'IA ce mois : $tours, $montant (${total.sansMontant} sans montant)';
}

/// Vrai si un poste de la politique est ouvert aux membres ; `null` tant que
/// la politique n'est pas lue.
bool? posteOuvertAuxMembres(AsyncValue<LectureIa<PolitiqueIa>> politique) {
  if (politique.isLoading && !politique.hasValue) return null;
  final doc = politique.value?.document;
  if (doc is! DocumentTrouve<PolitiqueIa>) return false;
  return doc.value.postes.values.any(
    (p) => p is ReglagePosteLu && p.reglage.ouvertAuxMembres,
  );
}

/// Ligne « IA ce mois » du menu du compte (ADR-016, section 6 ; amendement
/// « cadrage du lot A1 » d'ADR-015) : affichée à l'administrateur, à tout
/// membre quand un poste est ouvert, à tout membre qui a des tours ce mois.
/// `null` : la ligne n'est pas affichée. Pendant la lecture, rien n'est
/// affiché à un brasseur tant que son droit n'est pas connu.
String? texteIaCeMois({
  required bool admin,
  required AsyncValue<LectureIa<PolitiqueIa>> politique,
  required AsyncValue<LectureIa<CompteMoisIa>?> compte,
}) {
  final ouvert = admin ? true : posteOuvertAuxMembres(politique);
  final lu = compte.value?.document;
  if (compte.hasError && lu == null) {
    return ouvert == true ? 'IA ce mois : lecture impossible' : null;
  }
  if (lu == null) {
    return ouvert == true ? 'IA ce mois : lecture en cours' : null;
  }
  switch (lu) {
    case DocumentTrouve(:final value) when value.total.appels > 0:
      return texteComptesDuMois(value.total);
    case DocumentIllisibleTrouve():
      return 'IA ce mois : lecture impossible';
    case DocumentAbsentDuCache():
      return ouvert == true ? 'IA ce mois : indisponible hors ligne' : null;
    case DocumentTrouve() || DocumentAbsent():
      return ouvert == true ? 'IA ce mois : aucun tour' : null;
  }
}

/// Ligne du menu du compte, montée à l'ouverture du menu : la politique et le
/// compte du mois sont lus par `get()` à ce moment, sans écouteur.
class LigneIaCeMois extends ConsumerWidget {
  const LigneIaCeMois({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = ref.watch(
      grantedAccessProvider.select((a) => a?.member.isAdmin ?? false),
    );
    final texte = texteIaCeMois(
      admin: admin,
      politique: ref.watch(politiqueIaProvider),
      compte: ref.watch(compteMoisIaProvider),
    );
    if (texte == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        texte,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
