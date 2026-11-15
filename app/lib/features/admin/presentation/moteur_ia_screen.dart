import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/champ_nombre.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/encadre.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/garde_depart.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/ligne_liste.dart';
import '../../../core/providers.dart';
import '../../ai/data/ai_repository.dart';
import '../../ai/domain/reglages_ia.dart';
import '../../ai/presentation/ai_providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../../tickets/presentation/tickets_providers.dart';
import '../domain/postes_ia.dart';

/// Page des tarifs d'Anthropic, ouverte depuis la grille.
final kTarifsAnthropic = Uri.https('www.anthropic.com', '/pricing');

/// Proposition initiale du formulaire d'un poste sans réglage (ADR-016,
/// section 4, « Semis ») : elle ne s'applique qu'à l'appui sur
/// « Enregistrer ». Aucun serveur ne la lit ; ce n'est ni une borne ni une
/// valeur de repli (P60).
abstract final class PropositionInitiale {
  static const modele = 'claude-sonnet-5-5';
  static const effort = 'medium';
  static const toursParJour = 20;
  static const toursFondateur = 60;
  static const toursParConversation = 20;
}

/// Libellés d'Admin › Moteur d'IA.
abstract final class TextesMoteurIa {
  static const titre = 'Moteur d\'IA';
  static const sousTitre =
      'Modèle, plafonds et ouverture de chaque poste, grille des tarifs';
  static const chargement = 'Lecture des réglages de l\'IA';
  static const lectureImpossible = 'Impossible de lire les réglages de l\'IA.';
  static const actualiser = 'Actualiser';
  static const horsLigne =
      'Hors ligne. Réglages lus sur cet appareil : ils peuvent ne pas être à '
      'jour.';
  static const abandonTexte =
      'Les réglages modifiés ne seront pas enregistrés.';
  static const enregistrementHorsLigne = 'L\'enregistrement demande le réseau.';
  static const postes = 'Postes';
  static const grille = 'Grille tarifaire';
  static const nonEnregistre = 'Non enregistré';
  static const aucunReglage =
      'Aucun réglage enregistré : ce poste refuse tout appel.';
  static const reglageIllisible =
      'Réglage illisible : ce poste refuse tout appel. Enregistrez-le de '
      'nouveau.';
  static const modele = 'Modèle';
  static const ajouterModeleDabord = 'Ajoutez d\'abord un modèle à la grille.';
  static const modeleAbsent =
      'Modèle absent de la grille : les appels partent sans montant. '
      'Choisissez un modèle de la grille.';
  static const effort = 'Effort';
  static const sansEffort = 'Ce modèle n\'a pas de réglage d\'effort.';
  static const choisirEffort = 'Choisissez un effort.';
  static const toursParJour = 'Tours par jour et par membre';
  static const toursFondateur = 'Tours par jour du compte fondateur';
  static const toursParConversation = 'Tours par conversation';
  static const ouvert = 'Ouvert à tous les membres';
  static const ouvertNon = 'Seul l\'administrateur utilise ce poste.';
  static const ouvertOui =
      'Chaque membre l\'utilise, dans la limite de ses tours du jour.';
  static const enregistrer = 'Enregistrer';
  static const enregistrerGrille = 'Enregistrer la grille';
  static const enregistrement = 'Enregistrement';
  static const refus = 'Enregistrement refusé par le serveur.';
  static const reseau = 'Enregistrement impossible. Réessayez.';
  static const grilleEnregistree = 'Grille tarifaire enregistrée.';
  static const aReverifier =
      'Tarifs à revérifier : vérifiés il y a plus de 90 jours. Les appels '
      'restent chiffrés.';
  static const grilleAbsente =
      'Tarifs en panne : aucune grille enregistrée. Les appels partent sans '
      'montant.';
  static const grilleIllisible =
      'Tarifs en panne : grille illisible. Les appels partent sans montant.';
  static const recommencer = 'Recommencer la grille';
  static const ouvrirTarifs = 'Ouvrir les tarifs d\'Anthropic';
  static const source = 'Source';
  static const sourceParDefaut = 'Page des tarifs d\'Anthropic';
  static const verifieeLe = 'Tarifs vérifiés le';
  static const dateAbsente = 'Date à renseigner.';
  static const choisirDate = 'Choisir la date';
  static const aujourdhui = 'Aujourd\'hui';
  static const ajouterModele = 'Ajouter un modèle';
  static const retirer = 'Retirer';
  static const aucunModele = 'Aucun modèle dans la grille.';
  static const identifiant = 'Identifiant';
  static const aideIdentifiant =
      'Tel qu\'écrit sur la page d\'Anthropic, par exemple claude-sonnet-5-5.';
  static const nomAffiche = 'Nom affiché';
  static const entree = 'Entrée (\$ par million de jetons)';
  static const sortie = 'Sortie (\$ par million de jetons)';
  static const ecritureCache = 'Écriture du cache (\$ par million de jetons)';
  static const lectureCache = 'Lecture du cache (\$ par million de jetons)';
  static const effortsAcceptes = 'Efforts acceptés';
  static const aideEfforts =
      'Recopiez les efforts de la page d\'Anthropic, par exemple low, medium, '
      'high. Vide : modèle sans effort.';
  static const champObligatoire = 'Champ obligatoire.';
  static const identifiantPris = 'Ce modèle est déjà dans la grille.';
  static const ajouter = 'Ajouter';
  static const annuler = 'Annuler';

  static String verifiee(DateTime d) =>
      'Tarifs vérifiés le ${formatDateLongue(d)}';

  static String enregistres(String poste) =>
      'Réglages de « $poste » enregistrés.';

  static String retire(String libelle) => '« $libelle » retiré.';

  static String sertAuPoste(String poste) =>
      'Sert au poste « $poste » : choisissez-en un autre d\'abord.';

  static String ouvrirATous(String poste) =>
      'Ouvrir « $poste » à tous les membres ?';

  static String ouvrirATousTexte(String tours) =>
      'Chaque membre pourra faire $tours tours par jour. La limite de dépense '
      'de la Console Anthropic reste la borne.';

  static String tarifs(ModeleTarife m) {
    String p(double v) => '${formatNombre(v, decimales: 4)}$nbsp\$';
    return 'Entrée ${p(m.entree)} · Sortie ${p(m.sortie)} · Cache écrit '
        '${p(m.ecritureCache)} · Cache lu ${p(m.lectureCache)}, par million '
        'de jetons';
  }

  static String efforts(ModeleTarife m) => m.efforts.isEmpty
      ? 'Sans réglage d\'effort'
      : 'Efforts : ${m.efforts.join(', ')}';
}

/// Admin › Moteur d'IA (ADR-016, section 9) : réglage de chaque poste et
/// grille tarifaire, enregistrés par `saveAiSettings`. Lecture par `get()` ;
/// aucune liste de modèles ni d'efforts, aucun tarif ni borne de plafond en
/// Dart (P60) : menus tirés de la grille, refus lus dans `details.field`.
class MoteurIaScreen extends ConsumerStatefulWidget {
  const MoteurIaScreen({super.key});

  @override
  ConsumerState<MoteurIaScreen> createState() => _MoteurIaScreenState();
}

class _MoteurIaScreenState extends ConsumerState<MoteurIaScreen> {
  final _modifies = <String>{};

  /// Monte à chaque « Actualiser » : les sections repartent des valeurs lues,
  /// même si la lecture rend les mêmes valeurs.
  int _generation = 0;

  /// Confirmation de départ de la coquille (retour, navigation, menu du
  /// compte), posée tant qu'une section a des changements.
  late final GardeDepart _garde;

  @override
  void initState() {
    super.initState();
    _garde = ref.read(gardeDepartProvider);
  }

  @override
  void dispose() {
    _garde.retirer(this);
    super.dispose();
  }

  void _modifie(String section, bool dirty) {
    final avant = _modifies.isNotEmpty;
    dirty ? _modifies.add(section) : _modifies.remove(section);
    if (_modifies.isEmpty) {
      _garde.retirer(this);
    } else {
      _garde.poser(this, _confirmerDepart);
    }
    if (avant != _modifies.isNotEmpty) setState(() {});
  }

  /// « Abandonner les modifications ? » : vrai si rien n'est à perdre, ou si
  /// l'administrateur abandonne.
  Future<bool> _confirmerDepart() async {
    if (_modifies.isEmpty || !mounted) return true;
    // ticket: aucun (confirmation)
    final abandon = await confirmerAbandon(
      context,
      TextesMoteurIa.abandonTexte,
    );
    if (abandon && mounted) setState(_toutOublier);
    return abandon;
  }

  void _toutOublier() {
    _modifies.clear();
    _garde.retirer(this);
  }

  /// Relit les deux documents : les sections repartent des valeurs lues.
  /// Avec des changements non enregistrés, « Abandonner les modifications ? »
  /// d'abord.
  Future<void> _actualiser() async {
    if (!await _confirmerDepart() || !mounted) return;
    setState(() {
      _toutOublier();
      _generation++;
    });
    ref
      ..invalidate(politiqueIaProvider)
      ..invalidate(grilleIaProvider);
  }

  @override
  Widget build(BuildContext context) {
    final politiqueAsync = ref.watch(politiqueIaProvider);
    final grilleAsync = ref.watch(grilleIaProvider);
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final politique = politiqueAsync.value;
    final grille = grilleAsync.value;
    final Widget corps;
    if (politique == null || grille == null) {
      corps = politiqueAsync.hasError || grilleAsync.hasError
          ? EtatErreur(
              message: TextesMoteurIa.lectureImpossible,
              onRetry: () => unawaited(_actualiser()),
            )
          : const EtatChargement(label: TextesMoteurIa.chargement);
    } else {
      corps = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: politiqueAsync.isLoading || grilleAsync.isLoading
                  ? null
                  : () => unawaited(_actualiser()),
              icon: const Icon(Icons.refresh),
              label: const Text(TextesMoteurIa.actualiser),
            ),
          ),
          if (offline || politique.fromCache || grille.fromCache) ...[
            const Encadre(
              ton: TonEncadre.avertissement,
              icone: Icons.cloud_off_outlined,
              child: Text(TextesMoteurIa.horsLigne),
            ),
            const SizedBox(height: 8),
          ],
          ..._bandeauxGrille(grille.document),
          const TitreSection(TextesMoteurIa.postes),
          for (final poste in kPostesIa)
            _CartePoste(
              // Même lecture, même carte : une reconstruction de l'écran
              // garde la saisie ; une nouvelle lecture la remet à zéro.
              key: ValueKey((
                poste.cle,
                identityHashCode(politique),
                _generation,
              )),
              poste: poste,
              politique: politique.document,
              grille: switch (grille.document) {
                DocumentTrouve(:final value) => value,
                _ => null,
              },
              offline: offline,
              onModifie: (d) => _modifie('poste-${poste.cle}', d),
            ),
          const TitreSection(TextesMoteurIa.grille),
          _SectionGrille(
            key: ValueKey((identityHashCode(grille), _generation)),
            grille: grille.document,
            politique: switch (politique.document) {
              DocumentTrouve(:final value) => value,
              _ => null,
            },
            offline: offline,
            onModifie: (d) => _modifie('grille', d),
          ),
        ],
      );
    }
    return PopScope(
      canPop: _modifies.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmerDepart() && navigator.mounted) navigator.pop();
      },
      child: corps,
    );
  }

  List<Widget> _bandeauxGrille(RechercheDocument<GrilleTarifaire> grille) {
    final now = ref.read(horlogeProvider)();
    final (ton, texte) = switch (grille) {
      DocumentAbsent() => (TonEncadre.erreur, TextesMoteurIa.grilleAbsente),
      DocumentIllisibleTrouve() => (
        TonEncadre.erreur,
        TextesMoteurIa.grilleIllisible,
      ),
      DocumentTrouve(:final value) when value.aReverifier(now) => (
        TonEncadre.avertissement,
        TextesMoteurIa.aReverifier,
      ),
      _ => (null, null),
    };
    if (ton == null || texte == null) return const [];
    return [
      Encadre(
        ton: ton,
        icone: ton == TonEncadre.erreur
            ? Icons.error_outline
            : Icons.warning_amber_outlined,
        child: Text(texte),
      ),
      const SizedBox(height: 8),
    ];
  }
}

/// Messages d'un refus de `saveAiSettings`, par champ de formulaire.
typedef ErreursChamps = Map<String, String>;

/// Message d'un échec qui ne porte pas sur un champ du formulaire.
String messageEchec(EchecReglagesIa e) => switch (e.cause) {
  CauseEchecReglagesIa.reseau => TextesMoteurIa.reseau,
  _ => e.message ?? TextesMoteurIa.refus,
};

/// Carte d'un poste : modèle, effort, plafonds, ouverture aux membres.
class _CartePoste extends ConsumerStatefulWidget {
  const _CartePoste({
    super.key,
    required this.poste,
    required this.politique,
    required this.grille,
    required this.offline,
    required this.onModifie,
  });

  final PosteIa poste;
  final RechercheDocument<PolitiqueIa> politique;
  final GrilleTarifaire? grille;
  final bool offline;
  final ValueChanged<bool> onModifie;

  @override
  ConsumerState<_CartePoste> createState() => _CartePosteState();
}

class _CartePosteState extends ConsumerState<_CartePoste> {
  late final ReglagePosteIa? _enregistre;
  late final bool _illisible;
  String? _modele;
  String? _effort;
  late bool _ouvert;
  late final TextEditingController _jour;
  late final TextEditingController _fondateur;
  late final TextEditingController _conversation;
  ErreursChamps _erreurs = const {};
  String? _erreurGenerale;
  bool _enCours = false;

  /// Valeurs à l'ouverture de la carte (réglage enregistré, ou proposition
  /// initiale) : une valeur qui en diffère est un changement à perdre.
  late final Object _depart;

  /// Champs nommés par `details.field` (`features.<poste>.<champ>`), qui
  /// reçoivent le focus après un refus.
  final _focus = {
    for (final cle in [
      'model',
      'effort',
      'turns_per_day',
      'founder_turns_per_day',
      'turns_per_conversation',
      'members_enabled',
    ])
      cle: FocusNode(),
  };

  Object get _valeurs => (
    _modele,
    _effort,
    _ouvert,
    _jour.text.trim(),
    _fondateur.text.trim(),
    _conversation.text.trim(),
  );

  @override
  void initState() {
    super.initState();
    final doc = widget.politique;
    _enregistre = doc is DocumentTrouve<PolitiqueIa>
        ? doc.value.reglage(widget.poste.cle)
        : null;
    _illisible =
        doc is DocumentIllisibleTrouve<PolitiqueIa> ||
        (doc is DocumentTrouve<PolitiqueIa> &&
            doc.value.poste(widget.poste.cle) is ReglagePosteIllisible);
    final r = _enregistre;
    if (r != null) {
      _modele = r.modele;
      _effort = r.effort;
      _ouvert = r.ouvertAuxMembres;
    } else {
      final propose = widget.grille?.modele(PropositionInitiale.modele);
      _modele = propose?.id;
      _effort =
          propose != null &&
              propose.efforts.contains(PropositionInitiale.effort)
          ? PropositionInitiale.effort
          : null;
      _ouvert = false;
    }
    String t(int? v, int defaut) => '${v ?? defaut}';
    _jour = TextEditingController(
      text: t(r?.toursParJour, PropositionInitiale.toursParJour),
    );
    _fondateur = TextEditingController(
      text: t(r?.toursFondateurParJour, PropositionInitiale.toursFondateur),
    );
    _conversation = TextEditingController(
      text: t(
        r?.toursParConversation,
        PropositionInitiale.toursParConversation,
      ),
    );
    _depart = _valeurs;
  }

  @override
  void dispose() {
    for (final f in _focus.values) {
      f.dispose();
    }
    _jour.dispose();
    _fondateur.dispose();
    _conversation.dispose();
    super.dispose();
  }

  int? _entier(TextEditingController c) {
    final v = lireNombre(c.text).valeur;
    return v != null && v == v.truncateToDouble() && v > 0 ? v.toInt() : null;
  }

  /// Réglage saisi, ou `null` s'il manque une valeur.
  ReglagePosteIa? get _saisi {
    final modele = _modele;
    final jour = _entier(_jour);
    final fondateur = _entier(_fondateur);
    final conversation = _entier(_conversation);
    if (modele == null ||
        jour == null ||
        fondateur == null ||
        conversation == null) {
      return null;
    }
    final efforts = widget.grille?.modele(modele)?.efforts ?? const [];
    if (efforts.isNotEmpty && _effort == null) return null;
    return ReglagePosteIa(
      modele: modele,
      effort: efforts.isEmpty ? null : _effort,
      ouvertAuxMembres: _ouvert,
      toursParJour: jour,
      toursFondateurParJour: fondateur,
      toursParConversation: conversation,
    );
  }

  bool get _change {
    final s = _saisi;
    return _enregistre == null || s != _enregistre;
  }

  void _maj(VoidCallback f) {
    setState(() {
      f();
      _erreurs = const {};
      _erreurGenerale = null;
    });
    // Un poste « Non enregistré » compte aussi : une valeur changée depuis la
    // proposition initiale serait perdue.
    widget.onModifie(_valeurs != _depart);
  }

  Future<void> _enregistrer() async {
    final reglage = _saisi;
    if (reglage == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (reglage.ouvertAuxMembres && !(_enregistre?.ouvertAuxMembres ?? false)) {
      // ticket: aucun (confirmation)
      final ok = await confirmerAction(
        context,
        titre: TextesMoteurIa.ouvrirATous(widget.poste.libelle),
        paragraphes: [TextesMoteurIa.ouvrirATousTexte(_jour.text.trim())],
        libelle: 'Ouvrir et enregistrer',
      );
      if (!ok || !mounted) return;
    }
    final doc = widget.politique;
    setState(() => _enCours = true);
    try {
      await ref
          .read(aiRepositoryProvider)
          .enregistrer(
            kind: 'policy',
            value: PolitiqueIa.argument(
              actuelle: doc is DocumentTrouve<PolitiqueIa> ? doc.value : null,
              connus: [for (final p in kPostesIa) p.cle],
              cle: widget.poste.cle,
              reglage: reglage,
            ),
          );
    } on EchecReglagesIa catch (e) {
      // Déjà rapporté par le dépôt, sans valeur saisie.
      if (!mounted) return;
      final prefixe = 'features.${widget.poste.cle}.';
      final champ = e.champ;
      final cle =
          e.cause == CauseEchecReglagesIa.champ &&
              champ != null &&
              champ.startsWith(prefixe)
          ? champ.substring(prefixe.length)
          : null;
      setState(() {
        _enCours = false;
        if (cle != null) {
          _erreurs = {cle: e.message ?? TextesMoteurIa.refus};
        } else {
          _erreurGenerale = messageEchec(e);
        }
      });
      // Le champ en faute reçoit le focus, comme un champ refusé à la saisie.
      _focus[cle]?.requestFocus();
      return;
    }
    if (!mounted) return;
    setState(() => _enCours = false);
    widget.onModifie(false);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(TextesMoteurIa.enregistres(widget.poste.libelle))),
    );
    ref.invalidate(politiqueIaProvider);
  }

  Widget _champTours(TextEditingController c, String label, String cle) =>
      TextField(
        controller: c,
        focusNode: _focus[cle],
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          errorText:
              _erreurs[cle] ??
              erreurNombre(
                c.text,
                obligatoire: true,
                entier: true,
                minExclu: true,
              ),
          errorMaxLines: 3,
        ),
        onChanged: (_) => _maj(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grille = widget.grille;
    final modeles = grille?.modeles ?? const <ModeleTarife>[];
    final modele = _modele;
    final ligne = modele == null ? null : grille?.modele(modele);
    final absent = modele != null && ligne == null;
    final efforts = ligne?.efforts ?? const <String>[];
    final saisi = _saisi;
    final actif =
        !widget.offline &&
        !_enCours &&
        saisi != null &&
        (_change || _illisible);
    final large = MediaQuery.sizeOf(context).width >= kExpandedMinWidth;
    final plafonds = [
      _champTours(_jour, TextesMoteurIa.toursParJour, 'turns_per_day'),
      _champTours(
        _fondateur,
        TextesMoteurIa.toursFondateur,
        'founder_turns_per_day',
      ),
      _champTours(
        _conversation,
        TextesMoteurIa.toursParConversation,
        'turns_per_conversation',
      ),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // En lignes qui passent l'une sous l'autre : à 200 %, l'étiquette
            // ne prend pas la largeur du libellé.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(widget.poste.libelle, style: theme.textTheme.titleMedium),
                if (_enregistre == null && !_illisible)
                  // Ton d'avertissement, comme l'encadré du même nom.
                  const Etiquette(
                    label: TextesMoteurIa.nonEnregistre,
                    ton: TonEtiquette.tertiaire,
                  ),
              ],
            ),
            if (_enregistre == null) ...[
              const SizedBox(height: 8),
              Encadre(
                ton: TonEncadre.erreur,
                icone: Icons.error_outline,
                child: Text(
                  _illisible
                      ? TextesMoteurIa.reglageIllisible
                      : TextesMoteurIa.aucunReglage,
                ),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('modele-$modele-${modeles.length}'),
              focusNode: _focus['model'],
              initialValue: modele,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: TextesMoteurIa.modele,
                helperText: modeles.isEmpty
                    ? TextesMoteurIa.ajouterModeleDabord
                    : null,
                errorText:
                    _erreurs['model'] ??
                    (absent ? TextesMoteurIa.modeleAbsent : null),
                errorMaxLines: 3,
              ),
              items: [
                for (final m in modeles)
                  DropdownMenuItem(
                    value: m.id,
                    child: Text(
                      '${m.libelle} · ${m.id}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (absent)
                  DropdownMenuItem(
                    value: modele,
                    child: Text('$modele (absent de la grille)'),
                  ),
              ],
              onChanged: modeles.isEmpty
                  ? null
                  : (id) => _maj(() {
                      _modele = id;
                      final nouveaux = id == null
                          ? const <String>[]
                          : grille?.modele(id)?.efforts ?? const <String>[];
                      if (!nouveaux.contains(_effort)) _effort = null;
                    }),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('effort-$modele-$_effort'),
              focusNode: _focus['effort'],
              initialValue: efforts.contains(_effort) ? _effort : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: TextesMoteurIa.effort,
                helperText: ligne != null && efforts.isEmpty
                    ? TextesMoteurIa.sansEffort
                    : null,
                errorText:
                    _erreurs['effort'] ??
                    (efforts.isNotEmpty && _effort == null
                        ? TextesMoteurIa.choisirEffort
                        : null),
              ),
              items: [
                for (final e in efforts)
                  DropdownMenuItem(value: e, child: Text(e)),
              ],
              onChanged: efforts.isEmpty
                  ? null
                  : (e) => _maj(() => _effort = e),
            ),
            const SizedBox(height: 16),
            if (large)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, p) in plafonds.indexed) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: p),
                  ],
                ],
              )
            else
              for (final (i, p) in plafonds.indexed) ...[
                if (i > 0) const SizedBox(height: 16),
                p,
              ],
            const SizedBox(height: 8),
            SwitchListTile(
              focusNode: _focus['members_enabled'],
              contentPadding: EdgeInsets.zero,
              title: const Text(TextesMoteurIa.ouvert),
              subtitle: Text(
                _erreurs['members_enabled'] ??
                    (_ouvert
                        ? TextesMoteurIa.ouvertOui
                        : TextesMoteurIa.ouvertNon),
              ),
              value: _ouvert,
              onChanged: (v) => _maj(() => _ouvert = v),
            ),
            if (_erreurGenerale case final message?) ...[
              const SizedBox(height: 8),
              Encadre(
                ton: TonEncadre.erreur,
                icone: Icons.error_outline,
                liveRegion: true,
                child: Text(message),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: actif ? () => unawaited(_enregistrer()) : null,
                child: _enCours
                    ? const IndicateurBouton(
                        label: TextesMoteurIa.enregistrement,
                      )
                    : const Text(TextesMoteurIa.enregistrer),
              ),
            ),
            if (widget.offline)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  TextesMoteurIa.enregistrementHorsLigne,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Grille tarifaire : date de vérification, source, une ligne par modèle.
class _SectionGrille extends ConsumerStatefulWidget {
  const _SectionGrille({
    super.key,
    required this.grille,
    required this.politique,
    required this.offline,
    required this.onModifie,
  });

  final RechercheDocument<GrilleTarifaire> grille;
  final PolitiqueIa? politique;
  final bool offline;
  final ValueChanged<bool> onModifie;

  @override
  ConsumerState<_SectionGrille> createState() => _SectionGrilleState();
}

class _SectionGrilleState extends ConsumerState<_SectionGrille> {
  late List<ModeleTarife> _modeles;
  DateTime? _verifieeLe;
  late final TextEditingController _source;
  bool _modifiee = false;
  bool _recommencee = false;
  bool _enCours = false;
  String? _erreurChamp;
  String? _champEnFaute;
  String? _erreurGenerale;

  GrilleTarifaire? get _lue => switch (widget.grille) {
    DocumentTrouve(:final value) => value,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    final g = _lue;
    _modeles = [...?g?.modeles];
    _verifieeLe = g?.verifieeLe;
    _source = TextEditingController(
      text: g?.source ?? TextesMoteurIa.sourceParDefaut,
    );
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  void _maj(VoidCallback f) {
    setState(() {
      f();
      _modifiee = true;
      _erreurChamp = null;
      _champEnFaute = null;
      _erreurGenerale = null;
    });
    widget.onModifie(true);
  }

  /// Poste qui cite [id] dans la politique enregistrée, ou `null`.
  String? _posteQuiCite(String id) {
    for (final p in kPostesIa) {
      if (widget.politique?.reglage(p.cle)?.modele == id) return p.libelle;
    }
    return null;
  }

  Future<void> _ouvrirTarifs() async {
    final messenger = ScaffoldMessenger.of(context);
    final errors = ref.read(errorReportServiceProvider);
    Object? error;
    StackTrace? stackTrace;
    var ok = false;
    try {
      ok = await ref.read(ouvrirLienProvider)(kTarifsAnthropic);
    } catch (e, st) {
      error = e;
      stackTrace = st;
    }
    if (ok) return;
    errors.reportError(
      feature: 'admin.ai_pricing_link',
      error: error ?? StateError('ouverture refusée par le système'),
      stackTrace: stackTrace ?? StackTrace.current,
      context: 'page des tarifs d\'Anthropic',
    );
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Impossible d\'ouvrir le lien.')),
    );
  }

  Future<void> _choisirDate() async {
    final now = ref.read(horlogeProvider)();
    // ticket: aucun (sélecteur du système)
    final date = await showDatePicker(
      context: context,
      initialDate: _verifieeLe ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (date != null) _maj(() => _verifieeLe = date);
  }

  Future<void> _formulaire([int? index]) async {
    final initial = index == null ? null : _modeles[index];
    // ticket: /admin/moteur-ia/fenetre/modele
    final ligne = await showFeuilleOuDialogue<ModeleTarife>(
      context: context,
      fermetureProtegee: true,
      builder: (_) => _FormulaireModele(
        initial: initial,
        pris: {
          for (final m in _modeles)
            if (m.id != initial?.id) m.id,
        },
      ),
    );
    if (ligne == null || !mounted) return;
    _maj(() {
      if (index == null) {
        _modeles.add(ligne);
      } else {
        _modeles[index] = ligne;
      }
    });
  }

  void _retirer(int index) {
    final retire = _modeles[index];
    _maj(() => _modeles.removeAt(index));
    annoncerAvecAnnulation(
      ScaffoldMessenger.of(context),
      TextesMoteurIa.retire(retire.libelle),
      onAnnuler: () {
        if (!mounted) return;
        _maj(() => _modeles.insert(index.clamp(0, _modeles.length), retire));
      },
    );
  }

  Future<void> _enregistrer() async {
    final date = _verifieeLe;
    if (date == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final grille = GrilleTarifaire(
      verifieeLe: date,
      source: _source.text.trim(),
      modeles: List.unmodifiable(_modeles),
    );
    setState(() => _enCours = true);
    try {
      await ref
          .read(aiRepositoryProvider)
          .enregistrer(kind: 'pricing', value: grille.versArgument());
    } on EchecReglagesIa catch (e) {
      // Déjà rapporté par le dépôt, sans valeur saisie.
      if (!mounted) return;
      setState(() {
        _enCours = false;
        if (e.cause == CauseEchecReglagesIa.champ) {
          _champEnFaute = e.champ;
          _erreurChamp = e.message ?? TextesMoteurIa.refus;
        } else {
          _erreurGenerale = messageEchec(e);
        }
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _modifiee = false;
    });
    widget.onModifie(false);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text(TextesMoteurIa.grilleEnregistree)),
    );
    ref.invalidate(grilleIaProvider);
  }

  /// Erreur du serveur pour le modèle [id], ou `null`.
  String? _erreurModele(String id) {
    final champ = _champEnFaute;
    if (champ == null) return null;
    return champ == 'models.$id' || champ.startsWith('models.$id.')
        ? _erreurChamp
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final illisible =
        widget.grille is DocumentIllisibleTrouve<GrilleTarifaire> &&
        !_recommencee;
    if (illisible) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton(
          onPressed: () => setState(() => _recommencee = true),
          child: const Text(TextesMoteurIa.recommencer),
        ),
      );
    }
    final date = _verifieeLe;
    final actif =
        !widget.offline &&
        !_enCours &&
        date != null &&
        (_modifiee || _lue == null);
    final erreurGlobale =
        _erreurGenerale ??
        (_champEnFaute != null &&
                !_champEnFaute!.startsWith('models.') &&
                _champEnFaute != 'checked_on' &&
                _champEnFaute != 'source'
            ? _erreurChamp
            : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          date == null
              ? TextesMoteurIa.dateAbsente
              : TextesMoteurIa.verifiee(date),
          style: theme.textTheme.bodyLarge,
        ),
        if (_champEnFaute == 'checked_on')
          Text(
            _erreurChamp ?? TextesMoteurIa.refus,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => unawaited(_choisirDate()),
              child: const Text(TextesMoteurIa.choisirDate),
            ),
            OutlinedButton(
              onPressed: () => _maj(() {
                final now = ref.read(horlogeProvider)();
                _verifieeLe = DateTime(now.year, now.month, now.day);
              }),
              child: const Text(TextesMoteurIa.aujourdhui),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(_ouvrirTarifs()),
              icon: const Icon(Icons.open_in_new),
              label: const Text(TextesMoteurIa.ouvrirTarifs),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _source,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: TextesMoteurIa.source,
            errorText: _champEnFaute == 'source' ? _erreurChamp : null,
          ),
          onChanged: (_) => _maj(() {}),
        ),
        if (_modeles.isEmpty)
          Text(TextesMoteurIa.aucunModele, style: theme.textTheme.bodyLarge),
        for (final (i, m) in _modeles.indexed)
          LigneListe(
            titre: m.libelle,
            details: [
              Text(m.id),
              Text(TextesMoteurIa.tarifs(m)),
              Text(TextesMoteurIa.efforts(m)),
              if (_posteQuiCite(m.id) case final poste?)
                Text(TextesMoteurIa.sertAuPoste(poste)),
              if (_erreurModele(m.id) case final erreur?)
                Text(erreur, style: TextStyle(color: theme.colorScheme.error)),
            ],
            erreur: _erreurModele(m.id) != null,
            onTap: () => unawaited(_formulaire(i)),
            // ticket: /admin/moteur-ia/menu/modele
            action: PopupMenuButton<int>(
              tooltip: 'Actions sur ${m.libelle}',
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 0,
                  enabled: _posteQuiCite(m.id) == null,
                  child: const Text(TextesMoteurIa.retirer),
                ),
              ],
              onSelected: (_) => _retirer(i),
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => unawaited(_formulaire()),
            icon: const Icon(Icons.add),
            label: const Text(TextesMoteurIa.ajouterModele),
          ),
        ),
        if (erreurGlobale != null) ...[
          const SizedBox(height: 8),
          Encadre(
            ton: TonEncadre.erreur,
            icone: Icons.error_outline,
            liveRegion: true,
            child: Text(erreurGlobale),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            onPressed: actif ? () => unawaited(_enregistrer()) : null,
            child: _enCours
                ? const IndicateurBouton(label: TextesMoteurIa.enregistrement)
                : const Text(TextesMoteurIa.enregistrerGrille),
          ),
        ),
        if (widget.offline)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              TextesMoteurIa.enregistrementHorsLigne,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// Formulaire d'une ligne de la grille. Le client ne vérifie que la forme
/// des nombres ; identifiant, bornes des tarifs et efforts sont validés par le
/// serveur (P60).
class _FormulaireModele extends StatefulWidget {
  const _FormulaireModele({required this.initial, required this.pris});

  final ModeleTarife? initial;

  /// Identifiants déjà dans la grille.
  final Set<String> pris;

  @override
  State<_FormulaireModele> createState() => _FormulaireModeleState();
}

class _FormulaireModeleState extends State<_FormulaireModele> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _id;
  late final TextEditingController _libelle;
  late final TextEditingController _entree;
  late final TextEditingController _sortie;
  late final TextEditingController _ecriture;
  late final TextEditingController _lecture;
  late final TextEditingController _efforts;

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    String n(double? v) => v == null ? '' : formatNombre(v, decimales: 4);
    _id = TextEditingController(text: m?.id ?? '');
    _libelle = TextEditingController(text: m?.libelle ?? '');
    _entree = TextEditingController(text: n(m?.entree));
    _sortie = TextEditingController(text: n(m?.sortie));
    _ecriture = TextEditingController(text: n(m?.ecritureCache));
    _lecture = TextEditingController(text: n(m?.lectureCache));
    _efforts = TextEditingController(text: m?.efforts.join(', ') ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _id,
      _libelle,
      _entree,
      _sortie,
      _ecriture,
      _lecture,
      _efforts,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _valider() {
    if (!_form.currentState!.validate()) return;
    double v(TextEditingController c) => lireNombre(c.text).valeur!;
    Navigator.of(context).pop(
      ModeleTarife(
        id: _id.text.trim(),
        libelle: _libelle.text.trim(),
        entree: v(_entree),
        sortie: v(_sortie),
        ecritureCache: v(_ecriture),
        lectureCache: v(_lecture),
        efforts: [
          for (final e in _efforts.text.split(','))
            if (e.trim().isNotEmpty) e.trim(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ajout = widget.initial == null;
    Widget prix(TextEditingController c, String label) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ChampNombre(controller: c, label: label, obligatoire: true),
    );
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ajout ? TextesMoteurIa.ajouterModele : widget.initial!.libelle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _id,
            enabled: ajout,
            decoration: const InputDecoration(
              labelText: TextesMoteurIa.identifiant,
              helperText: TextesMoteurIa.aideIdentifiant,
              helperMaxLines: 3,
            ),
            validator: (t) {
              final v = t?.trim() ?? '';
              if (v.isEmpty) return TextesMoteurIa.champObligatoire;
              return widget.pris.contains(v)
                  ? TextesMoteurIa.identifiantPris
                  : null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _libelle,
            decoration: const InputDecoration(
              labelText: TextesMoteurIa.nomAffiche,
            ),
            validator: (t) => (t?.trim() ?? '').isEmpty
                ? TextesMoteurIa.champObligatoire
                : null,
          ),
          prix(_entree, TextesMoteurIa.entree),
          prix(_sortie, TextesMoteurIa.sortie),
          prix(_ecriture, TextesMoteurIa.ecritureCache),
          prix(_lecture, TextesMoteurIa.lectureCache),
          const SizedBox(height: 16),
          TextFormField(
            controller: _efforts,
            decoration: const InputDecoration(
              labelText: TextesMoteurIa.effortsAcceptes,
              helperText: TextesMoteurIa.aideEfforts,
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 24),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(TextesMoteurIa.annuler),
              ),
              FilledButton(
                onPressed: _valider,
                child: Text(
                  ajout ? TextesMoteurIa.ajouter : TextesMoteurIa.enregistrer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
