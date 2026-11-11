import 'dart:async';

import 'package:brewing/brewing.dart'
    show maxProcessSessions, processSessionOrder;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/editeur_plein_ecran.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/ligne_editeur.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../recipes/domain/chronologie.dart';
import '../../recipes/presentation/ingredient_forms.dart';
import '../domain/modele_exemple.dart';
import '../domain/modele_processus.dart';
import '../domain/preference_processus.dart';
import 'formulaire_journee.dart';
import 'libelles_processus.dart';
import 'process_detail_screen.dart';
import 'processes_providers.dart';

/// Nouveau processus ([id] nul, prérempli du modèle d'exemple si [exemple]) ou
/// modification d'un processus, en plein écran.
class ProcessEditorScreen extends ConsumerWidget {
  const ProcessEditorScreen({super.key, this.id, this.exemple = false});

  final String? id;
  final bool exemple;

  static const titreNouveau = 'Nouveau processus';
  static const titreModifier = 'Modifier le processus';
  static const readOnlyMessage = 'Seul l\'auteur modifie ce processus.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = this.id;
    if (id == null) return _Editeur(initial: null, exemple: exemple);
    final access = ref.watch(grantedAccessProvider);
    return PageDocument<ModeleProcessus>(
      async: ref.watch(processTemplatesProvider),
      id: id,
      offline: access?.offline ?? false,
      textes: textesProcessus,
      onRetry: () => ref.invalidate(processTemplatesProvider),
      onBack: () => context.go(AppRoutes.processes),
      frame: (state) => EditeurPleinEcran(
        titre: titreModifier,
        closePath: AppRoutes.processes,
        fermerParRetour: true,
        body: state,
      ),
      builder: (context, modele) {
        if (modele.ownerUid != access?.user.uid) {
          return EditeurPleinEcran(
            titre: titreModifier,
            closePath: AppRoutes.process(id),
            fermerParRetour: true,
            body: EtatVide(
              icon: Icons.lock_outline,
              message: readOnlyMessage,
              action: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => context.go(AppRoutes.process(id)),
                child: const Text('Voir le processus'),
              ),
            ),
          );
        }
        return _Editeur(key: ValueKey(id), initial: modele, exemple: false);
      },
    );
  }
}

/// Journée en cours d'édition.
class _Journee {
  _Journee({
    required this.key,
    required this.name,
    required this.offsetDays,
    required this.elements,
  }) : requiresRecipeBlock = false;

  _Journee.de(JourneeModele j)
    : key = j.key,
      name = j.name,
      offsetDays = j.offsetDays,
      requiresRecipeBlock = j.requiresRecipeBlock,
      elements = [...j.elements];

  final String key;
  String name;
  int offsetDays;
  bool requiresRecipeBlock;
  final List<ElementModele> elements;

  /// Bloc de la recette porté par la journée, ou `null`.
  NatureElement? get bloc {
    for (final e in elements) {
      if (e.estBloc) return e.nature;
    }
    return null;
  }

  JourneeModele toModele() => JourneeModele(
    key: key,
    name: name,
    offsetDays: offsetDays,
    requiresRecipeBlock: requiresRecipeBlock && bloc != null,
    elements: List.unmodifiable(elements),
  );
}

class _Editeur extends ConsumerStatefulWidget {
  const _Editeur({super.key, required this.initial, required this.exemple});

  final ModeleProcessus? initial;
  final bool exemple;

  @override
  ConsumerState<_Editeur> createState() => _EditeurState();
}

class _EditeurState extends ConsumerState<_Editeur> {
  final _formKey = GlobalKey<FormState>();
  final _nameField = GlobalKey<FormFieldState<String>>();
  final _nameFocus = FocusNode();
  final _journeeKeys = <String, GlobalKey>{};
  final _scroll = ScrollController();
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late final List<_Journee> _journees;
  bool _dirty = false;
  bool _saving = false;

  /// Choix de l'interrupteur « Proposer par défaut » ; `null` tant que
  /// l'utilisateur n'y a pas touché.
  bool? _parDefautChoisi;

  static const nameMissing = 'Donnez un nom au processus.';
  static const maxJournees = '$maxProcessSessions journées au plus.';
  static const maxEtapes =
      '$kMaxElementsJourneeModele étapes au plus dans une journée.';
  static const choixIllisible = 'Votre choix actuel n\'a pas pu être lu.';

  String _newKey() => ref.read(processesRepositoryProvider).newKey();

  @override
  void initState() {
    super.initState();
    final ContenuModele? depart =
        widget.initial?.content ??
        (widget.exemple ? modeleExemple(_newKey) : null);
    _name = TextEditingController(text: depart?.name ?? '');
    _notes = TextEditingController(text: depart?.notes ?? '');
    _journees = depart == null
        ? [
            _Journee(
              key: _newKey(),
              name: 'Brassage',
              offsetDays: 0,
              elements: [
                ElementModele.bloc(
                  key: _newKey(),
                  nature: NatureElement.chronologieRecette,
                ),
              ],
            ),
          ]
        : [for (final j in depart.journees) _Journee.de(j)];
    // Le modèle d'exemple n'est écrit qu'à « Enregistrer » : le quitter demande
    // confirmation.
    _dirty = widget.initial == null && widget.exemple;
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _nameFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _mutate(VoidCallback change) => setState(() {
    change();
    _dirty = true;
  });

  void _changed([Object? _]) {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _annoncer(String message) => unawaited(
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    ),
  );

  void _snack(String message, {SnackBarAction? action}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(persist: false, content: Text(message), action: action),
    );
  }

  /// Trie les journées 2 et suivantes par écart, à égalité dans l'ordre actuel ;
  /// la journée du brassage reste la première. Annonce les journées déplacées,
  /// sauf [nouvelle].
  void _trier({String? nouvelle}) {
    final avant = [for (final j in _journees) j.key];
    // Ordre de `brewing/`, le même que la résolution (P3) : journée de brassage
    // en tête, puis par écart, à égalité dans l'ordre courant.
    final ordre = processSessionOrder([
      for (final j in _journees) j.offsetDays,
    ]);
    final ranges = [for (final i in ordre) _journees[i]];
    _journees
      ..clear()
      ..addAll(ranges);
    final messages = [
      for (final (i, j) in _journees.indexed)
        if (j.key != nouvelle &&
            avant.contains(j.key) &&
            avant.indexOf(j.key) != i)
          '« ${j.name} » passe en journée ${i + 1}.',
    ];
    if (messages.isNotEmpty) _snack(messages.join(' '));
  }

  Future<void> _ouvrirJournee([int? index]) {
    final journee = index == null ? null : _journees[index];
    // ticket: /processus/nouveau/fenetre/journee, /processus/:id/modifier/fenetre/journee
    return showFeuilleOuDialogue<void>(
      context: context,
      builder: (_) => FormulaireJournee(
        initialName: journee?.name,
        initialOffset: journee?.offsetDays,
        offsetFixe: index == 0,
        onSubmit: (saisie) => _mutate(() {
          if (journee == null) {
            final key = _newKey();
            _journees.add(
              _Journee(
                key: key,
                name: saisie.name,
                offsetDays: saisie.offsetDays,
                elements: [],
              ),
            );
            _trier(nouvelle: key);
          } else {
            journee
              ..name = saisie.name
              ..offsetDays = saisie.offsetDays;
            if (index != 0) _trier();
          }
        }),
      ),
    );
  }

  void _retirerJournee(int index) {
    final removed = _journees[index];
    _mutate(() => _journees.removeAt(index));
    _snack(
      'Journée « ${removed.name} » retirée.',
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () {
          if (!mounted) return;
          _mutate(() {
            _journees.insert(index.clamp(1, _journees.length), removed);
            _trier(nouvelle: removed.key);
          });
        },
      ),
    );
  }

  void _deplacerJournee(int from, int to) {
    _mutate(() {
      final j = _journees.removeAt(from);
      _journees.insert(to, j);
    });
    _annoncer('« ${_journees[to].name} » en position ${to + 1}.');
  }

  Future<void> _ouvrirEtape(_Journee journee, [int? index]) =>
      // ticket: /processus/nouveau/fenetre/etape, /processus/:id/modifier/fenetre/etape
      showFeuilleOuDialogue<void>(
        context: context,
        builder: (_) => FormulaireEtape(
          initial: index == null ? null : ligneEtape(journee.elements[index]),
          remaining: kMaxElementsJourneeModele - journee.elements.length,
          newKey: _newKey,
          onSubmit: (line) => _mutate(() {
            if (index == null) {
              journee.elements.add(elementEtape(line));
            } else {
              journee.elements[index] = elementEtape(line);
            }
          }),
        ),
      );

  void _deplacerElement(_Journee journee, int from, int to) {
    _mutate(() {
      final e = journee.elements.removeAt(from);
      journee.elements.insert(to, e);
    });
    final e = journee.elements[to];
    _annoncer(
      '« ${e.estBloc ? nomBloc(e.nature) : e.name} » en position '
      '${to + 1}.',
    );
  }

  void _dupliquerEtape(_Journee journee, int index) {
    if (journee.elements.length >= kMaxElementsJourneeModele) return;
    final e = journee.elements[index];
    _mutate(
      () => journee.elements.insert(
        index + 1,
        ElementModele.etape(
          key: _newKey(),
          name: e.name!,
          durationMin: e.durationMin!,
          tempC: e.tempC,
        ),
      ),
    );
  }

  void _retirerElement(_Journee journee, int index) {
    final removed = journee.elements[index];
    final condition = journee.requiresRecipeBlock;
    _mutate(() {
      journee.elements.removeAt(index);
      // Sans bloc, la journée n'est plus conditionnée à la recette.
      if (removed.estBloc) journee.requiresRecipeBlock = false;
    });
    _snack(
      '« ${removed.estBloc ? nomBloc(removed.nature) : removed.name} » retiré.',
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () {
          if (!mounted || !_journees.contains(journee)) return;
          _mutate(() {
            journee.elements.insert(
              index.clamp(0, journee.elements.length),
              removed,
            );
            if (removed.estBloc) journee.requiresRecipeBlock = condition;
          });
        },
      ),
    );
  }

  void _insererBloc(_Journee journee, NatureElement nature) {
    _mutate(
      () => journee.elements.add(
        ElementModele.bloc(key: _newKey(), nature: nature),
      ),
    );
    _annoncer(
      '${nomBloc(nature)} ajouté en position ${journee.elements.length}.',
    );
  }

  /// Journée qui porte déjà le bloc [nature], ou `null`.
  _Journee? _journeeDuBloc(NatureElement nature) {
    for (final j in _journees) {
      if (j.elements.any((e) => e.nature == nature)) return j;
    }
    return null;
  }

  /// Vrai si le lecteur n'a aucun processus par défaut, lu avec certitude ;
  /// faux s'il en a un ; `null` si son choix n'a pas pu être lu (lecture en
  /// cours, cache seul, document illisible, panne, liste non lue) : rien ne
  /// doit alors remplacer un défaut peut-être existant.
  bool? _aucunDefautLu() {
    final uid = ref.read(grantedAccessProvider)?.user.uid;
    if (uid == null) return null;
    switch (ref.read(processPreferenceProvider(uid)).value) {
      case DocumentAbsent<PreferenceProcessus>():
        return true;
      case DocumentTrouve<PreferenceProcessus>(:final value):
        final defaultId = value.defaultTemplateId;
        if (defaultId == null) return true;
        final list = ref.read(processTemplatesProvider).value;
        if (list == null) return null;
        if (list.valides.any((m) => m.id == defaultId && m.ownerUid == uid)) {
          return false;
        }
        // Absent d'une lecture du serveur : supprimé, ou d'un autre membre.
        return list.fromCache ? null : true;
      default:
        return null;
    }
  }

  /// La journée [key] à l'écran. Les listes d'étapes au-dessus d'elle ne sont
  /// mesurées qu'une fois affichées : un second défilement corrige le premier.
  Future<void> _montrerJournee(String key) async {
    await montrerChamp(_journeeKeys[key]?.currentContext);
    if (!mounted) return;
    await montrerChamp(_journeeKeys[key]?.currentContext);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    // Le contrôleur décide, même si le champ n'est pas construit ; la
    // validation du formulaire affiche le message sous le champ.
    if (_name.text.trim().isEmpty) {
      _formKey.currentState?.validate();
      if (_scroll.hasClients) _scroll.jumpTo(0);
      await montrerChamp(_nameField.currentContext);
      _nameFocus.requestFocus();
      return;
    }
    for (final j in _journees) {
      if (j.elements.isNotEmpty) continue;
      _snack('La journée « ${j.name} » n\'a aucune étape.');
      await _montrerJournee(j.key);
      return;
    }
    final notes = _notes.text.trim();
    final content = ContenuModele(
      name: _name.text.trim(),
      notes: notes.isEmpty ? null : notes,
      journees: [for (final j in _journees) j.toModele()],
    );
    final erreur = erreurModele(content);
    if (erreur != null) {
      _snack(erreur);
      return;
    }
    final access = ref.read(grantedAccessProvider);
    if (access == null) return;
    final initial = widget.initial;
    final aucunDefaut = _aucunDefautLu();
    final parDefaut =
        initial == null &&
        aucunDefaut != null &&
        (_parDefautChoisi ?? aucunDefaut);
    setState(() => _saving = true);
    // Nom du jeton, celui que comparent les règles ; nul s'il n'y en a pas ou si
    // le jeton ne peut pas être lu (déjà rapporté).
    final ownerName = await ref.read(authRepositoryProvider).currentTokenName();
    if (!mounted) return;
    final repository = ref.read(processesRepositoryProvider);
    final String id;
    final Future<void> written;
    if (initial == null) {
      final created = repository.create(
        content: content,
        ownerUid: access.user.uid,
        ownerName: ownerName,
      );
      id = created.id;
      written = created.written;
      if (parDefaut) {
        final pref = ref
            .read(preferencesProcessusRepositoryProvider)
            .saveDefault(uid: access.user.uid, templateId: id);
        unawaited(
          pref.catchError((Object _) {
            // Déjà rapportée par le dépôt ; le refus s'affiche.
            messenger.showSnackBar(
              const SnackBar(
                content: Text(ProcessDetailScreen.defaultRejected),
              ),
            );
          }),
        );
      }
    } else {
      id = initial.id;
      written = repository.update(
        id: id,
        content: content,
        ownerName: ownerName,
      );
    }
    suivreEcriture(
      messenger: messenger,
      written: written,
      succes: access.offline
          ? 'Processus enregistré sur l\'appareil. Il partira au retour du '
                'réseau.'
          : 'Processus enregistré.',
      refus: 'L\'enregistrement de « ${content.name} » a échoué.',
    );
    setState(() {
      _saving = false;
      _dirty = false;
    });
    context.go(AppRoutes.process(id));
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    final uid = ref.watch(grantedAccessProvider)?.user.uid;
    if (initial == null && uid != null) {
      // Lus pour cocher « Proposer par défaut » quand le lecteur n'en a aucun.
      ref.watch(processPreferenceProvider(uid));
      ref.watch(processTemplatesProvider);
    }
    final atMaxJournees = _journees.length >= maxProcessSessions;
    final aucunDefaut = initial == null ? _aucunDefautLu() : null;
    // Préférence en lecture, ou lue alors que la liste des processus, qui dit
    // si le défaut existe encore, est en lecture.
    final prefEnLecture =
        uid != null &&
        ((ref.read(processPreferenceProvider(uid)) is AsyncLoading &&
                ref.read(processPreferenceProvider(uid)).value == null) ||
            (ref.read(processTemplatesProvider) is AsyncLoading &&
                ref.read(processTemplatesProvider).value == null));
    return EditeurPleinEcran(
      titre: initial == null
          ? ProcessEditorScreen.titreNouveau
          : ProcessEditorScreen.titreModifier,
      closePath: initial == null
          ? AppRoutes.processes
          : AppRoutes.process(initial.id),
      fermerParRetour: true,
      dirty: _dirty,
      saving: _saving,
      onSave: _save,
      abandonMessage:
          'Les changements de ce processus ne seront pas '
          'enregistrés.',
      body: Form(
        key: _formKey,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kEditorMaxWidth),
            // Une liste d'étapes par journée, dans un seul défilement : un
            // glisser fait défiler l'éditeur.
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: _nameField,
                          controller: _name,
                          focusNode: _nameFocus,
                          autofocus: initial == null && !widget.exemple,
                          maxLength: kNomModeleMaxLength,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Nom du processus',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              (v ?? '').trim().isEmpty ? nameMissing : null,
                          onChanged: _changed,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _notes,
                          maxLength: kNotesModeleMaxLength,
                          minLines: 2,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'Notes (facultatif)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: _changed,
                        ),
                        if (initial == null)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              ProcessDetailScreen.proposerParDefaut,
                            ),
                            subtitle: Text(
                              aucunDefaut != null
                                  ? ProcessDetailScreen.choixPersonnel
                                  : prefEnLecture
                                  ? ProcessDetailScreen.lectureDefaut
                                  : choixIllisible,
                            ),
                            value:
                                aucunDefaut != null &&
                                (_parDefautChoisi ?? aucunDefaut),
                            onChanged: aucunDefaut == null
                                ? null
                                : (v) => setState(() => _parDefautChoisi = v),
                          ),
                      ],
                    ),
                  ),
                ),
                for (final (i, j) in _journees.indexed)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: _BlocJournee(
                      enTete: _journeeKeys.putIfAbsent(j.key, GlobalKey.new),
                      journee: j,
                      index: i,
                      total: _journees.length,
                      journeeDuBloc: _journeeDuBloc,
                      onEditer: () => _ouvrirJournee(i),
                      onRetirer: i == 0 ? null : () => _retirerJournee(i),
                      onMonter:
                          i > 1 && _journees[i - 1].offsetDays == j.offsetDays
                          ? () => _deplacerJournee(i, i - 1)
                          : null,
                      onDescendre:
                          i > 0 &&
                              i < _journees.length - 1 &&
                              _journees[i + 1].offsetDays == j.offsetDays
                          ? () => _deplacerJournee(i, i + 1)
                          : null,
                      onAjouterEtape: () => _ouvrirEtape(j),
                      onOuvrirEtape: (k) => _ouvrirEtape(j, k),
                      onDeplacer: (from, to) => _deplacerElement(j, from, to),
                      onDupliquer: (k) => _dupliquerEtape(j, k),
                      onRetirerElement: (k) => _retirerElement(j, k),
                      onInsererBloc: (n) => _insererBloc(j, n),
                      onCondition: (v) =>
                          _mutate(() => j.requiresRecipeBlock = v),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (atMaxJournees)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: TexteAbsent(maxJournees),
                          ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          onPressed: atMaxJournees ? null : _ouvrirJournee,
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter une journée'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Une journée de l'éditeur, en slivers : en-tête, étapes (liste réordonnable,
/// interrupteur sous le bloc), boutons du bas.
class _BlocJournee extends StatelessWidget {
  const _BlocJournee({
    required this.enTete,
    required this.journee,
    required this.index,
    required this.total,
    required this.journeeDuBloc,
    required this.onEditer,
    required this.onRetirer,
    required this.onMonter,
    required this.onDescendre,
    required this.onAjouterEtape,
    required this.onOuvrirEtape,
    required this.onDeplacer,
    required this.onDupliquer,
    required this.onRetirerElement,
    required this.onInsererBloc,
    required this.onCondition,
  });

  /// Clé de l'en-tête : l'éditeur y défile pour une journée vide.
  final GlobalKey enTete;
  final _Journee journee;
  final int index;
  final int total;
  final _Journee? Function(NatureElement) journeeDuBloc;
  final VoidCallback onEditer;
  final VoidCallback? onRetirer;
  final VoidCallback? onMonter;
  final VoidCallback? onDescendre;
  final VoidCallback onAjouterEtape;
  final ValueChanged<int> onOuvrirEtape;
  final void Function(int from, int to) onDeplacer;
  final ValueChanged<int> onDupliquer;
  final ValueChanged<int> onRetirerElement;
  final ValueChanged<NatureElement> onInsererBloc;
  final ValueChanged<bool> onCondition;

  bool get _brassage => index == 0;

  /// Détails d'une étape : décalage depuis le début de la journée, ou depuis
  /// la fin de la chronologie de la recette, dont la durée n'est connue qu'au
  /// brassin ; durées calculées par `brewing/` (P3).
  Map<String, String> _decalages() {
    final result = <String, String>{};
    var segment = <ElementModele>[];
    var apresChronologie = false;
    void flush() {
      final offsets = decalagesChronologie([
        for (final e in segment) ligneEtape(e),
      ]);
      for (final (i, e) in segment.indexed) {
        final d = '+${formatDuree(offsets[i])}';
        result[e.key] = apresChronologie
            ? '$d après la chronologie de la recette'
            : d;
      }
      segment = [];
    }

    for (final e in journee.elements) {
      if (e.nature == NatureElement.chronologieRecette) {
        flush();
        apresChronologie = true;
      } else if (!e.estBloc) {
        segment.add(e);
      }
    }
    flush();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elements = journee.elements;
    final atMax = elements.length >= kMaxElementsJourneeModele;
    final decalages = _decalages();
    final ecart = 'J+${journee.offsetDays}';
    final retirer = onRetirer;
    final monter = onMonter;
    final descendre = onDescendre;

    final header = Padding(
      key: enTete,
      padding: const EdgeInsets.only(top: 24, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              label:
                  'Journée ${index + 1} sur $total, ${journee.name}, '
                  '${_brassage ? '$ecart, jour du brassage' : ecart}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _brassage
                        ? '${index + 1}. ${journee.name}'
                        : '${index + 1}. ${journee.name} · $ecart',
                    style: theme.textTheme.titleMedium,
                  ),
                  if (_brassage)
                    Text(
                      '$ecart, jour du brassage',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // ticket: /processus/nouveau/menu/journee, /processus/:id/modifier/menu/journee
          PopupMenuButton<VoidCallback>(
            tooltip: 'Actions sur la journée « ${journee.name} »',
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: onEditer,
                child: Text(
                  _brassage ? 'Renommer la journée' : 'Modifier la journée',
                ),
              ),
              if (monter != null)
                PopupMenuItem(value: monter, child: const Text('Monter')),
              if (descendre != null)
                PopupMenuItem(value: descendre, child: const Text('Descendre')),
              if (retirer != null)
                PopupMenuItem(
                  value: retirer,
                  child: const Text('Retirer la journée'),
                ),
            ],
          ),
        ],
      ),
    );

    Widget ligne(BuildContext context, int i) {
      final e = elements[i];
      final up = i == 0 ? null : () => onDeplacer(i, i - 1);
      final down = i == elements.length - 1 ? null : () => onDeplacer(i, i + 1);
      final Widget row;
      if (e.estBloc) {
        final obligatoire = e.nature == NatureElement.chronologieRecette;
        final details = [
          if (obligatoire) 'Obligatoire dans la journée de brassage',
        ];
        row = LigneEditeur(
          title: nomBloc(e.nature),
          details: details,
          icone: iconeBloc,
          semanticsLabel: [blocParle(e.nature), ...details].join(', '),
          onMoveUp: up,
          onMoveDown: down,
          onRemove: obligatoire ? null : () => onRetirerElement(i),
        );
      } else {
        row = LigneEditeur(
          title: '${i + 1}. ${e.name}',
          details: [?decalages[e.key], ...detailsEtape(e)],
          onTap: () => onOuvrirEtape(i),
          onDuplicate: atMax ? null : () => onDupliquer(i),
          onMoveUp: up,
          onMoveDown: down,
          onRemove: () => onRetirerElement(i),
        );
      }
      final condition = e.estBloc ? texteCondition(e.nature) : null;
      return Column(
        key: ValueKey(e.key),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: i,
                child: const SizedBox.square(
                  dimension: 48,
                  child: Icon(Icons.drag_handle),
                ),
              ),
              Expanded(child: row),
            ],
          ),
          // Sous son bloc, il le suit quand le bloc se déplace.
          if (condition != null)
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Seulement si la recette en a'),
                subtitle: Text(condition),
                value: journee.requiresRecipeBlock,
                onChanged: onCondition,
              ),
            ),
        ],
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (mentionCondition(journee.toModele()) case final mention?)
                Text(
                  mention,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
            ],
          ),
        ),
        SliverReorderableList(
          itemCount: elements.length,
          onReorderItem: onDeplacer,
          itemBuilder: ligne,
          proxyDecorator: (child, _, _) => Material(elevation: 4, child: child),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (atMax)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: TexteAbsent(_EditeurState.maxEtapes),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: atMax ? null : onAjouterEtape,
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter une étape'),
                  ),
                  if (!_brassage)
                    _MenuBloc(
                      journee: journee,
                      actif: !atMax,
                      journeeDuBloc: journeeDuBloc,
                      onInserer: onInsererBloc,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// « Insérer un bloc de la recette » : houblons à cru ou ajouts à
/// l'embouteillage, chacun une fois dans le modèle, un seul par journée.
class _MenuBloc extends StatelessWidget {
  const _MenuBloc({
    required this.journee,
    required this.actif,
    required this.journeeDuBloc,
    required this.onInserer,
  });

  final _Journee journee;
  final bool actif;
  final _Journee? Function(NatureElement) journeeDuBloc;
  final ValueChanged<NatureElement> onInserer;

  @override
  Widget build(BuildContext context) {
    final autre = journee.bloc;
    // ticket: /processus/nouveau/menu/bloc, /processus/:id/modifier/menu/bloc
    return MenuAnchor(
      menuChildren: [
        for (final nature in const [
          NatureElement.houblonsACru,
          NatureElement.ajoutsEmbouteillage,
        ])
          () {
            final placee = journeeDuBloc(nature);
            final String? raison = placee != null
                ? 'Déjà dans « ${placee.name} »'
                : autre != null
                ? 'Une journée porte un seul bloc de la recette.'
                : null;
            return MenuItemButton(
              leadingIcon: const Icon(iconeBloc),
              onPressed: raison == null ? () => onInserer(nature) : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(nomBloc(nature)),
                  if (raison != null)
                    Text(raison, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            );
          }(),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: actif
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        icon: const Icon(iconeBloc),
        label: const Text('Insérer un bloc de la recette'),
      ),
    );
  }
}
