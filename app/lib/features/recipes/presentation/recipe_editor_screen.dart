import 'dart:async';
import 'dart:math';

import 'package:exchange/exchange.dart' show IndexImport, MarqueIa;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/champ_nombre.dart';
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
import '../../../core/data/lecture_document.dart';
import '../../admin/domain/postes_ia.dart';
import '../../ai/domain/reglages_ia.dart';
import '../../ai/presentation/ai_providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../../equipment/domain/equipment.dart';
import '../../equipment/presentation/equipment_providers.dart';
import '../../library/domain/referentiel.dart';
import '../../library/presentation/champ_bibliotheque.dart';
import '../domain/assistant_recette.dart';
import '../domain/import_recettes.dart' show indexBibliotheque;
import '../domain/beerjson.dart';
import '../domain/libelles_etapes.dart';
import '../domain/recipe.dart';
import 'assistant_controleur.dart';
import 'carte_proposition.dart';
import 'contenu_recette.dart';
import 'ingredient_forms.dart';
import 'panneau_assistant.dart';
import 'recipe_calculations_view.dart';
import 'recipe_detail_screen.dart';
import 'recipes_providers.dart';

/// Nouvelle recette ([id] nul) ou modification d'une recette, en plein écran.
class RecipeEditorScreen extends ConsumerWidget {
  const RecipeEditorScreen({super.key, this.id, this.retourParPop = false});

  final String? id;

  /// Vrai : ouvert depuis la fiche importée ; « Enregistrer » ferme l'éditeur
  /// par `pop` pour garder le compte rendu de l'import sous la fiche.
  final bool retourParPop;

  static const readOnlyMessage = 'Seul l\'auteur modifie cette recette.';

  /// Champ « Description aromatique » (`aroma_description`).
  static const aromaLabel = 'Description aromatique (facultatif)';
  static const aromaAide =
      'Ce que l\'on sent et goûte : agrumes, caramel, épices… Le filtre '
      '« Arômes » de la liste cherche dans ce texte.';
  static const aromaTropLongue =
      'La description aromatique dépasse $kRecipeAromaMaxLength caractères.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = this.id;
    if (id == null) return const _RecipeEditor(initial: null);
    final access = ref.watch(grantedAccessProvider);
    return PageDocument<Recipe>(
      async: ref.watch(recipesListProvider),
      id: id,
      offline: access?.offline ?? false,
      textes: textesRecette,
      onRetry: () => ref.invalidate(recipesListProvider),
      onBack: () => context.go(AppRoutes.recipes),
      frame: (state) => EditeurPleinEcran(
        titre: 'Modifier la recette',
        closePath: AppRoutes.recipes,
        body: state,
      ),
      builder: (context, recipe) {
        if (recipe.ownerUid != access?.user.uid) {
          return EditeurPleinEcran(
            titre: 'Modifier la recette',
            closePath: AppRoutes.recipe(id),
            body: EtatVide(
              icon: Icons.lock_outline,
              message: readOnlyMessage,
              action: FilledButton(
                onPressed: () => context.go(AppRoutes.recipe(id)),
                child: const Text('Voir la recette'),
              ),
            ),
          );
        }
        return _RecipeEditor(
          key: ValueKey(id),
          initial: recipe,
          retourParPop: retourParPop,
        );
      },
    );
  }
}

class _RecipeEditor extends ConsumerStatefulWidget {
  const _RecipeEditor({
    super.key,
    required this.initial,
    this.retourParPop = false,
  });

  final Recipe? initial;
  final bool retourParPop;

  @override
  ConsumerState<_RecipeEditor> createState() => _RecipeEditorState();
}

/// Sections de l'éditeur, dans l'ordre des puces de saut.
enum _Section { general, fermentables, hops, others, yeast, steps, notes }

class _RecipeEditorState extends ConsumerState<_RecipeEditor> {
  final _formKey = GlobalKey<FormState>();
  final _keys = {for (final s in _Section.values) s: GlobalKey()};
  final _nameKey = GlobalKey();
  final _nameFocus = FocusNode();
  final _styleFocus = FocusNode();
  late final TextEditingController _name;
  late final TextEditingController _style;
  late final TextEditingController _volume;
  late final TextEditingController _boil;
  late final TextEditingController _grainTemp;
  late final TextEditingController _notes;
  late final TextEditingController _aroma;
  // Listes modifiées en place, jamais remplacées : « Annuler » après un retrait
  // réinsère la ligne dans la liste que l'écran affiche.
  late final List<FermentableLine> _fermentables;
  late final List<HopLine> _hops;
  late final List<OtherLine> _others;
  late final List<YeastLine> _yeasts;
  late final List<MashStep> _steps;
  String? _type;
  String? _equipmentId;
  bool _equipmentTouched = false;
  bool _dirty = false;
  bool _saving = false;
  String? _nameError;

  /// Conversation de l'assistant (ADR-015), créée à la première ouverture du
  /// panneau et perdue à la fermeture de l'éditeur.
  ControleurAssistant? _assistant;

  /// Réponses de l'assistant déjà vues par l'éditeur : une réponse arrivée
  /// fenêtre fermée s'annonce avec « Ouvrir ».
  int _reponsesVues = 0;

  /// Dernier échec déjà vu ou annoncé.
  EchecAssistant? _echecVu;

  /// Message « Proposition appliquée… Annuler » affiché, et annonce de
  /// l'assistant affichée : `null` une fois fermés.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _annonceAnnuler;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _annonceAssistant;

  /// Annonce arrivée pendant « Annuler » : affichée à sa fermeture, sauf si
  /// l'assistant s'est rouvert entre-temps.
  String? _annoncePendante;

  /// Marques « proposée par l'IA » du brouillon (ADR-015, lot A2).
  late List<MarqueIa> _marques;

  /// Brouillon de référence des marques : la recette chargée, ou le
  /// brouillon d'après la dernière proposition appliquée. Une valeur changée
  /// depuis perd sa marque (`marquesRevues`).
  late RecipeContent _reference;

  /// Ce que l'éditeur a fait de chaque proposition, par conversation et rang
  /// de la réponse ([_cleProposition]) : une proposition d'une nouvelle
  /// conversation part sans état.
  final Map<String, EtatApplication> _applications = {};

  static String _cleProposition(String conversation, int rang) =>
      '$conversation|$rang';

  /// Conversation vue au dernier changement du contrôleur : quand elle change
  /// (« Nouvelle conversation », « Résumer et continuer »), la proposition
  /// appliquée ne s'annule plus.
  String? _conversationVue;

  /// Causes déjà rapportées par [_revoir] pendant cette session de l'éditeur.
  final Set<String> _revuesRapportees = {};

  /// Dernière proposition appliquée, seule à pouvoir s'annuler.
  ({
    int message,
    String conversation,
    RecipeContent avant,
    RecipeContent referenceAvant,
    bool dirtyAvant,
    String? empreinteApres,
  })?
  _derniere;

  /// Bibliothèque entière lue pour les aperçus, gardée tant que l'éditeur
  /// est ouvert ; relue par « Réessayer ».
  Future<IndexImport?>? _indexProposition;

  /// Contexte de la fenêtre de l'assistant ouverte (feuille du bas sous
  /// 840 px, grande fenêtre au-delà), fermée après « Appliquer ».
  BuildContext? _fenetre;
  final _assistantFocus = FocusNode();

  /// Monte quand l'état des propositions change (annulation) : la fenêtre,
  /// construite par sa route, se reconstruit sans attendre le contrôleur.
  final _etatPropositions = ValueNotifier<int>(0);
  final Set<String> _calculsProposition = {};

  /// Brouillon, calculs et équipement de la dernière construction : ce que
  /// lit le bloc Calculs, envoyé à l'assistant (U13).
  ({
    RecipeContent content,
    CalculsRecette calculs,
    EquipementRecette equipement,
  })?
  _dernier;

  static const nameMissing = 'Donnez un nom à la recette.';

  /// Aide du champ « Style ».
  static const styleAide =
      'Tapez un code (21A) ou un nom, puis choisissez une suggestion, ou '
      'ouvrez la liste des styles. L\'export BeerXML demande un style de la '
      'Bibliothèque.';

  @override
  void initState() {
    super.initState();
    final c = widget.initial?.content;
    _name = TextEditingController(text: c?.name ?? '');
    _style = TextEditingController(text: c?.style ?? '');
    _volume = TextEditingController(text: texteSaisi(c?.batchVolumeL));
    _boil = TextEditingController(text: texteSaisi(c?.boilTimeMin));
    _grainTemp = TextEditingController(text: texteSaisi(c?.grainTempC));
    _notes = TextEditingController(text: c?.notes ?? '');
    _aroma = TextEditingController(text: c?.aromaDescription ?? '');
    _fermentables = [...?c?.fermentables];
    _hops = [...?c?.hops];
    _others = [...?c?.others];
    _yeasts = [...?c?.yeasts];
    _steps = [...?c?.mashSteps];
    _equipmentId = c?.equipmentId;
    _type = c?.type;
    _marques = [...?c?.aiProposed];
    _reference = c ?? const RecipeContent(name: '');
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _style,
      _volume,
      _boil,
      _grainTemp,
      _notes,
      _aroma,
    ]) {
      c.dispose();
    }
    _nameFocus.dispose();
    _styleFocus.dispose();
    _assistantFocus.dispose();
    _etatPropositions.dispose();
    _assistant
      ?..removeListener(_assistantChange)
      ..dispose();
    super.dispose();
  }

  void _assistantChange() {
    if (!mounted) return;
    final conversation = _assistant?.idConversation;
    if (_conversationVue != null && conversation != _conversationVue) {
      if (_derniere != null) {
        // L'annonce « Annuler » de la proposition appliquée ne vaut plus.
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _derniere = null;
      }
    }
    _conversationVue = conversation;
    final a = _assistant;
    if (a != null) {
      final recues = a.reponsesRecues;
      final echec = a.echec;
      String? annonce;
      if (recues != _reponsesVues) {
        _reponsesVues = recues;
        annonce = a.dernierMode == ModeAssistant.resume
            ? TextesAssistant.resumeRecu
            : a.derniereAvecProposition
            ? TextesAssistant.reponseAvecProposition
            : TextesAssistant.reponseRecue;
      } else if (echec != null && !identical(echec, _echecVu)) {
        annonce = TextesAssistant.echecFenetreFermee;
      }
      _echecVu = echec;
      if (annonce != null) _annoncerFenetreFermee(annonce);
    }
    setState(() {});
  }

  /// Réponse, résumé ou échec arrivé fenêtre fermée : annoncé avec « Ouvrir »,
  /// qui rouvre l'assistant. Pendant « Proposition appliquée… Annuler », il
  /// attend sa fermeture, sans la couper.
  void _annoncerFenetreFermee(String annonce) {
    if (_fenetre != null) return;
    if (_annonceAnnuler != null) {
      _annoncePendante = annonce;
      return;
    }
    final controleur = annoncerAvecAction(
      ScaffoldMessenger.of(context),
      annonce,
      action: TextesAssistant.ouvrirReponse,
      onAction: () {
        if (mounted && _fenetre == null) {
          _ouvrirAssistant(MediaQuery.sizeOf(context).width);
        }
      },
    );
    _annonceAssistant = controleur;
    unawaited(
      controleur.closed.then((_) {
        if (identical(_annonceAssistant, controleur)) _annonceAssistant = null;
      }),
    );
  }

  ControleurAssistant get _controleur => _assistant ??=
      ControleurAssistant(
          repository: ref.read(assistantRepositoryProvider),
          errorReportService: ref.read(errorReportServiceProvider),
        )
        ..empreinteBrouillon = _empreinteActuelle
        ..addListener(_assistantChange);

  String? _empreinteActuelle() {
    final dernier = _dernier;
    if (dernier == null) return null;
    return empreinteBrouillon(
      dernier.content,
      ref.read(errorReportServiceProvider),
    );
  }

  // ------------------------------------------------------------ propositions

  /// Les quatre index de la Bibliothèque, hors ligne depuis le cache seul ;
  /// `null` si l'un manque ou ne se lit pas : l'aperçu affiche la panne, sans
  /// repli sur la valeur du modèle.
  Future<IndexImport?> _index({bool relire = false}) {
    if (relire || _indexProposition == null) {
      _indexProposition = _lireIndex();
    }
    return _indexProposition!;
  }

  Future<IndexImport?> _lireIndex() async {
    final repository = ref.read(libraryRepositoryProvider);
    final offline = ref.read(grantedAccessProvider)?.offline ?? false;
    const natures = [
      NatureReferentiel.fermentables,
      NatureReferentiel.hops,
      NatureReferentiel.miscs,
      NatureReferentiel.cultures,
    ];
    final List<RechercheDocument<IndexReferentiel>> lus;
    try {
      lus = await Future.wait([
        for (final n in natures) repository.lireIndex(n, cacheSeul: offline),
      ]);
    } catch (_) {
      // Déjà rapportée par le dépôt de la Bibliothèque : `lireIndex` rapporte
      // chaque panne avant de la relancer. L'aperçu affiche la panne.
      return null;
    }
    final index = [
      for (final l in lus)
        if (l case DocumentTrouve(:final value)) indexBibliotheque(value),
    ];
    if (index.length != natures.length) return null;
    return IndexImport(
      malts: index[0],
      houblons: index[1],
      ajouts: index[2],
      levures: index[3],
    );
  }

  CalculsRecette _calculer(RecipeContent content) => evaluerRecette(
    content,
    _dernier?.equipement ?? const SansEquipement(),
    errors: ref.read(errorReportServiceProvider),
    reported: _calculsProposition,
    recipeKey: 'proposition',
  );

  /// Carte de la proposition de la réponse de rang [rang], s'il y en a une.
  Widget? _carte(int rang) {
    final controleur = _assistant;
    final recue = controleur?.propositions[rang];
    if (controleur == null || recue == null) return null;
    return CarteProposition(
      key: ValueKey('proposition-${controleur.idConversation}-$rang'),
      recue: recue,
      brouillon: () => _dernier?.content,
      index: _index,
      calculer: _calculer,
      errors: ref.read(errorReportServiceProvider),
      etat: _applications[_cleProposition(controleur.idConversation, rang)],
      onAppliquer: (apercu) => _appliquer(rang, apercu),
      onAnnuler: () => unawaited(_annuler(rang)),
    );
  }

  /// Remplace les champs et les listes de l'éditeur par [c].
  void _charger(RecipeContent c) {
    _name.text = c.name;
    _nameError = null;
    _style.text = c.style ?? '';
    _volume.text = texteSaisi(c.batchVolumeL);
    _boil.text = texteSaisi(c.boilTimeMin);
    _grainTemp.text = texteSaisi(c.grainTempC);
    _notes.text = c.notes ?? '';
    _aroma.text = c.aromaDescription ?? '';
    _type = c.type;
    _replace(_fermentables, sortFermentables(c.fermentables));
    _replace(_hops, sortHops(c.hops));
    _replace(_others, c.others);
    _replace(_yeasts, c.yeasts);
    _replace(_steps, c.mashSteps);
    _marques = [...c.aiProposed];
  }

  /// « Appliquer au brouillon » : aucun appel au modèle, aucune écriture.
  void _appliquer(int rang, ApercuPret apercu) {
    final dernier = _dernier;
    final controleur = _assistant;
    if (dernier == null || controleur == null) return;
    final precedente = _derniere;
    final cle = _cleProposition(controleur.idConversation, rang);
    setState(() {
      if (precedente != null) {
        final avant = _cleProposition(
          precedente.conversation,
          precedente.message,
        );
        if (_applications[avant] == EtatApplication.appliquee) {
          _applications[avant] = EtatApplication.remplacee;
        }
      }
      _derniere = (
        message: rang,
        conversation: controleur.idConversation,
        avant: dernier.content,
        referenceAvant: _reference,
        dirtyAvant: _dirty,
        empreinteApres: empreinteBrouillon(
          apercu.apres,
          ref.read(errorReportServiceProvider),
        ),
      );
      _applications[cle] = EtatApplication.appliquee;
      _charger(apercu.apres);
      _reference = apercu.apres;
      _dirty = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    final annonce = annoncerAvecAnnulation(
      messenger,
      TextesProposition.annonceAppliquee,
      onAnnuler: () => unawaited(_annuler(rang)),
    );
    _annonceAnnuler = annonce;
    unawaited(
      annonce.closed.then((_) {
        if (!identical(_annonceAnnuler, annonce)) return;
        _annonceAnnuler = null;
        final pendante = _annoncePendante;
        _annoncePendante = null;
        if (mounted && pendante != null) _annoncerFenetreFermee(pendante);
      }),
    );
    // La feuille ou la fenêtre se ferme ; la conversation reste dans le
    // contrôleur, et le focus revient sur l'icône Assistant.
    final fenetre = _fenetre;
    if (fenetre != null && fenetre.mounted) Navigator.of(fenetre).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _assistantFocus.requestFocus();
    });
  }

  /// « Annuler la proposition » : le brouillon d'avant revient. Après une
  /// modification à la main, une confirmation d'abord.
  Future<void> _annuler(int rang) async {
    final derniere = _derniere;
    final controleur = _assistant;
    if (derniere == null ||
        controleur == null ||
        derniere.message != rang ||
        derniere.conversation != controleur.idConversation ||
        _applications[_cleProposition(derniere.conversation, rang)] !=
            EtatApplication.appliquee) {
      return;
    }
    final modifie = _empreinteActuelle() != derniere.empreinteApres;
    if (modifie &&
        // ticket: aucun (confirmation)
        !await confirmerAction(
          context,
          titre: TextesProposition.confirmerAnnulation,
          paragraphes: const [TextesProposition.confirmerAnnulationTexte],
          libelle: TextesProposition.annuler,
        )) {
      return;
    }
    if (!mounted || _derniere != derniere) return;
    setState(() {
      _charger(derniere.avant);
      _reference = derniere.referenceAvant;
      _dirty = derniere.dirtyAvant;
      _applications[_cleProposition(derniere.conversation, rang)] =
          EtatApplication.annulee;
      _derniere = null;
    });
    // Après le build de l'éditeur, qui réécrit `_dernier` : la fenêtre se
    // reconstruit avec la ligne des calculs du brouillon rendu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _etatPropositions.value++;
    });
  }

  /// Marques revues du dernier brouillon construit (ADR-015, lot A2).
  List<MarqueIa> get _marquesAffichees =>
      _dernier?.content.aiProposed ?? _marques;

  /// Marques du brouillon [c] après les modifications faites depuis
  /// [_reference] (valeur corrigée à la main, ingrédient retiré).
  RecipeContent _revoir(RecipeContent c) {
    try {
      return c.marquesRevues(_reference);
    } catch (error, stackTrace) {
      // Ligne refusée à l'écriture : les marques restent telles quelles.
      // L'éditeur reconstruit à chaque frappe : un rapport par cause et par
      // session, comme les calculs (`evaluerRecette`).
      if (_revuesRapportees.add('${error.runtimeType}')) {
        ref
            .read(errorReportServiceProvider)
            .reportError(
              feature: 'recipes.ai_proposed',
              error: error,
              stackTrace: stackTrace,
              context: 'marques non revues : ${error.runtimeType}',
            );
      }
      return c;
    }
  }

  /// La conversation a un tour, un résumé ou un appel en cours : la quitter la
  /// perd.
  bool get _conversationAPerdre {
    final a = _assistant;
    return a != null && (a.aDuContenu || a.enCours);
  }

  String get _reponsePerdue => _assistant?.enCours ?? false
      ? ' La réponse en attente sera perdue ; le tour est compté.'
      : '';

  /// Départ avec une conversation (✕, retour, menu du compte).
  Future<bool> _confirmerDepart(BuildContext context) => _dirty
      // ticket: aucun (confirmation)
      ? confirmerAbandon(
          context,
          'Les changements de cette recette ne seront pas enregistrés. La '
          'conversation avec l\'assistant sera perdue.$_reponsePerdue',
        )
      // ticket: aucun (confirmation)
      : confirmerAbandon(
          context,
          'La conversation avec l\'assistant sera perdue. Elle n\'est '
          'enregistrée nulle part.$_reponsePerdue',
          titre: 'Quitter l\'éditeur ?',
          continuer: 'Rester',
          abandonner: 'Quitter',
        );

  Future<ContexteAssistant?> _contexteAssistant() async {
    final dernier = _dernier;
    if (dernier == null) {
      // L'éditeur n'a pas encore été construit : rien à envoyer. Rapporté
      // ici, sans texte ; le panneau affiche « La recette contient une valeur
      // refusée… ».
      ref
          .read(errorReportServiceProvider)
          .reportError(
            feature: 'recipes.assistant',
            error: StateError('brouillon de l\'éditeur non lu'),
            stackTrace: StackTrace.current,
            context: 'contexte demandé avant la première construction',
          );
      return null;
    }
    return contexteAssistant(
      content: dernier.content,
      calculs: dernier.calculs,
      equipement: dernier.equipement,
      library: ref.read(libraryRepositoryProvider),
      errors: ref.read(errorReportServiceProvider),
    );
  }

  /// Icône « Assistant » de la barre du haut : feuille du bas sous 840 px,
  /// grande fenêtre au-delà (ADR-015, amendement du 2026-11-22). La politique
  /// et les tours du jour sont relus à chaque ouverture ; rien n'est envoyé.
  /// Fermer la fenêtre ne perd rien : la conversation vit dans le contrôleur.
  void _ouvrirAssistant(double width) {
    final controleur = _controleur;
    _reponsesVues = controleur.reponsesRecues;
    _echecVu = controleur.echec;
    // Réponse déjà lue en rouvrant : son annonce, affichée ou en attente,
    // est retirée.
    _annoncePendante = null;
    _annonceAssistant?.close();
    ref
      ..invalidate(politiqueIaProvider)
      ..invalidate(quotasIaProvider);
    Widget panneau(BuildContext fenetreContext, {required bool autofocus}) =>
        ValueListenableBuilder<int>(
          valueListenable: _etatPropositions,
          builder: (_, _, _) =>
              _panneau(controleur, fenetreContext, autofocus: autofocus),
        );

    final Future<void> ouverte;
    if (width >= kExpandedMinWidth) {
      // ticket: /recettes/nouvelle/fenetre/assistant, /recettes/:id/modifier/fenetre/assistant
      ouverte = showDialog<void>(
        context: context,
        builder: (dialogContext) {
          _fenetre = dialogContext;
          final taille = MediaQuery.sizeOf(dialogContext);
          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            clipBehavior: Clip.antiAlias,
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: TextesAssistant.titre,
              child: SizedBox(
                width: min(taille.width - 48, kAssistantFenetreLargeur),
                height: taille.height * _hauteurFenetre,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: panneau(dialogContext, autofocus: true),
                ),
              ),
            ),
          );
        },
      );
    } else {
      // ticket: /recettes/nouvelle/fenetre/assistant, /recettes/:id/modifier/fenetre/assistant
      ouverte = showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) {
          _fenetre = sheetContext;
          final hauteur = MediaQuery.sizeOf(sheetContext).height;
          final clavier = MediaQuery.viewInsetsOf(sheetContext).bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: clavier),
            child: SizedBox(
              height: (hauteur - clavier).clamp(
                0.0,
                hauteur * kFeuilleListeHauteur,
              ),
              child: panneau(sheetContext, autofocus: false),
            ),
          );
        },
      );
    }
    unawaited(
      ouverte.then((_) {
        _fenetre = null;
        _reponsesVues = _assistant?.reponsesRecues ?? _reponsesVues;
        _echecVu = _assistant?.echec;
        // La fermeture rend le focus à l'icône Assistant.
        if (mounted && width >= kExpandedMinWidth) {
          _assistantFocus.requestFocus();
        }
      }),
    );
  }

  /// Panneau de la feuille ou de la fenêtre, avec le dernier brouillon lu.
  Widget _panneau(
    ControleurAssistant controleur,
    BuildContext fenetreContext, {
    required bool autofocus,
  }) {
    final dernier = _dernier;
    return PanneauAssistant(
      controleur: controleur,
      resumeCalculs: dernier == null
          ? ''
          : texteBarreCalculs(dernier.calculs).texte,
      recetteVide: _recetteVide(dernier?.content),
      contexte: _contexteAssistant,
      carteProposition: _carte,
      autofocus: autofocus,
      onFermer: () => Navigator.of(fenetreContext).pop(),
    );
  }

  /// Hauteur de la fenêtre de l'assistant : 90 % de la fenêtre.
  static const _hauteurFenetre = 0.9;

  static bool _recetteVide(RecipeContent? c) =>
      c == null || (c.fermentables.isEmpty && c.hops.isEmpty);

  void _changed([Object? _]) => setState(() => _dirty = true);

  /// Équipement retenu : celui de la recette, ou, pour une nouvelle recette, le
  /// seul équipement du brasseur tant qu'il n'a rien choisi.
  String? _effectiveEquipmentId(List<Equipment> mine) {
    if (_equipmentTouched || widget.initial != null) return _equipmentId;
    return _equipmentId ?? (mine.length == 1 ? mine.single.id : null);
  }

  RecipeContent _content(String? equipmentId) {
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final initial = widget.initial?.content;
    return RecipeContent(
      name: _name.text.trim(),
      type: _type,
      style: text(_style),
      notes: text(_notes),
      aromaDescription: text(_aroma),
      batchVolumeL: _positive(_volume.text),
      boilTimeMin: _withinBoil(_boil.text),
      grainTempC: _grainTemperature(_grainTemp.text),
      equipmentId: equipmentId,
      fermentables: List.unmodifiable(_fermentables),
      hops: List.unmodifiable(_hops),
      others: List.unmodifiable(_others),
      yeasts: List.unmodifiable(_yeasts),
      mashSteps: List.unmodifiable(_steps),
      importedFrom: initial?.importedFrom,
      // Conservé d'un import, sans champ de saisie (I9).
      author: initial?.author,
      aiProposed: List.unmodifiable(_marques),
    );
  }

  /// Volume lisible et accepté par le formulaire, sinon absent du calcul.
  double? _positive(String text) => erreurNombre(text, minExclu: true) == null
      ? lireNombre(text).valeur
      : null;

  int? _withinBoil(String text) =>
      erreurNombre(text, max: 600, entier: true) == null
      ? lireNombre(text).valeur?.round()
      : null;

  /// Bornes de la température du grain (°C).
  static const _grainTempMin = -20.0;
  static const _grainTempMax = 60.0;

  double? _grainTemperature(String text) =>
      erreurNombre(text, min: _grainTempMin, max: _grainTempMax) == null
      ? lireNombre(text).valeur
      : null;

  Future<void> _scrollTo(GlobalKey key) => montrerChamp(key.currentContext);

  Future<void> _save(String? equipmentId) async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = nameMissing);
      await _scrollTo(_nameKey);
      if (mounted) _nameFocus.requestFocus();
      return;
    }
    // Tous les champs sont construits (colonne défilante) : un champ hors écran
    // est validé aussi. L'écran défile jusqu'au premier en erreur.
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await montrerChamp(invalid.first.context);
      return;
    }
    // La conversation n'est perdue qu'après une recette prête à enregistrer.
    if (_conversationAPerdre &&
        // ticket: aucun (confirmation)
        !await confirmerAbandon(
          context,
          'La recette sera enregistrée. La conversation sera perdue : copiez '
          'd\'abord ce que vous voulez garder.$_reponsePerdue',
          titre: 'Enregistrer et effacer la conversation ?',
          continuer: 'Revenir à la recette',
          abandonner: 'Enregistrer',
        )) {
      return;
    }
    if (!mounted) return;
    final access = ref.read(grantedAccessProvider);
    if (access == null) return;
    // Marques revues contre la référence : une valeur corrigée à la main ou un
    // ingrédient retiré perd sa marque (ADR-015, section 6).
    final content = _revoir(_content(equipmentId));
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    // Nom du jeton, celui que comparent les règles ; nul s'il n'y en a pas ou si
    // le jeton ne peut pas être lu (déjà rapporté).
    final ownerName = await ref.read(authRepositoryProvider).currentTokenName();
    if (!mounted) return;
    final repository = ref.read(recipesRepositoryProvider);
    final initial = widget.initial;
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
          ? RecipeDetailScreen.savedOffline
          : RecipeDetailScreen.saved,
      refus: RecipeDetailScreen.saveRejected(content.name),
    );
    setState(() {
      _saving = false;
      _dirty = false;
    });
    if (widget.retourParPop && context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.recipe(id));
    }
  }

  // ------------------------------------------------------------ lignes

  // ticket: /recettes/nouvelle/fenetre/malt, /recettes/:id/modifier/fenetre/malt
  Future<void> _openFermentable([int? index]) => showFeuilleOuDialogue<void>(
    context: context,
    builder: (_) => FormulaireFermentescible(
      initial: index == null ? null : _fermentables[index],
      champsProposes: index == null
          ? const {}
          : {
              for (final champ in const ['color', 'yield'])
                if (fermentableProposeParIa(
                  _marquesAffichees,
                  _fermentables[index],
                  champ,
                ))
                  champ,
            },
      remaining: kMaxFermentables - _fermentables.length,
      onSubmit: (line) => setState(() {
        final list = [..._fermentables];
        index == null ? list.add(line) : list[index] = line;
        _replace(_fermentables, sortFermentables(list));
        _dirty = true;
      }),
    ),
  );

  // ticket: /recettes/nouvelle/fenetre/houblon, /recettes/:id/modifier/fenetre/houblon
  Future<void> _openHop([int? index]) => showFeuilleOuDialogue<void>(
    context: context,
    builder: (_) => FormulaireHoublon(
      initial: index == null ? null : _hops[index],
      alphaPropose:
          index != null && houblonProposeParIa(_marquesAffichees, _hops[index]),
      remaining: kMaxHops - _hops.length,
      recipeBoilMin: _withinBoil(_boil.text),
      onSubmit: (line) => setState(() {
        final list = [..._hops];
        index == null ? list.add(line) : list[index] = line;
        _replace(_hops, sortHops(list));
        _dirty = true;
      }),
    ),
  );

  // ticket: /recettes/nouvelle/fenetre/ajout, /recettes/:id/modifier/fenetre/ajout
  Future<void> _openOther([int? index]) => showFeuilleOuDialogue<void>(
    context: context,
    builder: (_) => FormulaireAjout(
      initial: index == null ? null : _others[index],
      remaining: kMaxOthers - _others.length,
      onSubmit: (line) => setState(() {
        index == null ? _others.add(line) : _others[index] = line;
        _dirty = true;
      }),
    ),
  );

  // ticket: /recettes/nouvelle/fenetre/levure, /recettes/:id/modifier/fenetre/levure
  Future<void> _openYeast() => showFeuilleOuDialogue<void>(
    context: context,
    builder: (_) => FormulaireLevure(
      initial: _yeasts.isEmpty ? null : _yeasts.first,
      attenuationProposee:
          _yeasts.isNotEmpty &&
          levureProposeeParIa(_marquesAffichees, _yeasts.first),
      // Une seule levure (A3) : la saisie remplace la première.
      onSubmit: (line) => setState(() {
        _replace(_yeasts, [line, ..._yeasts.skip(1)]);
        _dirty = true;
      }),
    ),
  );

  // ticket: /recettes/nouvelle/fenetre/palier, /recettes/:id/modifier/fenetre/palier
  Future<void> _openStep([int? index]) => showFeuilleOuDialogue<void>(
    context: context,
    builder: (_) => FormulairePalier(
      initial: index == null ? null : _steps[index],
      remaining: kMaxMashSteps - _steps.length,
      onSubmit: (line) => setState(() {
        index == null ? _steps.add(line) : _steps[index] = line;
        _dirty = true;
      }),
    ),
  );

  /// Retire une ligne sans confirmation ; la SnackBar propose « Annuler ».
  void _remove<T>(
    List<T> list,
    int index,
    String name, {
    List<T> Function(List<T>)? sort,
  }) {
    final removed = list[index];
    setState(() {
      list.removeAt(index);
      _dirty = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        persist: false,
        content: Text('« $name » retiré.'),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () {
            if (!mounted) return;
            setState(() {
              list.insert(index.clamp(0, list.length), removed);
              if (sort != null) {
                _replace(list, sort(list));
              }
            });
          },
        ),
      ),
    );
  }

  void _duplicateLine<T>(
    List<T> list,
    int index,
    int max, {
    List<T> Function(List<T>)? sort,
  }) {
    if (list.length >= max) return;
    setState(() {
      list.insert(index + 1, list[index]);
      if (sort != null) {
        _replace(list, sort(list));
      }
      _dirty = true;
    });
  }

  /// Remplace le contenu de [target] par [items], en place.
  static void _replace<T>(List<T> target, Iterable<T> items) {
    final copy = items.toList();
    target
      ..clear()
      ..addAll(copy);
  }

  void _moveStep(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _steps.length) return;
    setState(() {
      final step = _steps.removeAt(index);
      _steps.insert(target, step);
      _dirty = true;
    });
  }

  // ------------------------------------------------------------ affichage

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(grantedAccessProvider);
    final equipmentAsync = ref.watch(equipmentListProvider);
    final readerUid = access?.user.uid;
    final allEquipment = (equipmentAsync.value?.valides ?? <Equipment>[])
      ..sort(compareEquipment(readerUid));
    final mine = [
      for (final e in allEquipment)
        if (e.ownerUid == readerUid) e,
    ];
    final equipmentId = _effectiveEquipmentId(mine);
    final equipement = equipementDe(
      equipmentId,
      equipmentAsync,
      offline: access?.offline ?? false,
    );
    final content = _revoir(_content(equipmentId));
    final calculs = evaluerRecette(
      content,
      equipement,
      errors: ref.read(errorReportServiceProvider),
      reported: ref.read(calculationReportsProvider),
      recipeKey: widget.initial?.id ?? 'nouvelle',
    );
    _dernier = (content: content, calculs: calculs, equipement: equipement);
    final initial = widget.initial;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= kExpandedMinWidth;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // Bouton visible pour l'administrateur ; pour un brasseur, seulement si
    // la politique lue ouvre le poste (ADR-015, section 2).
    final politique = ref.watch(politiqueIaProvider).value?.document;
    final assistantVisible =
        (access?.member.isAdmin ?? false) ||
        (politique is DocumentTrouve<PolitiqueIa> &&
            (politique.value
                    .reglage(kPosteAssistantRecette)
                    ?.ouvertAuxMembres ??
                false));

    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _JumpChips(
            counts: {
              _Section.fermentables: _fermentables.length,
              _Section.hops: _hops.length,
              _Section.others: _others.length,
              _Section.yeast: _yeasts.length,
              _Section.steps: _steps.length,
            },
            onJump: (s) => _scrollTo(_keys[s]!),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _sections(
                  calculs: calculs,
                  equipment: allEquipment,
                  readerUid: readerUid,
                  equipmentId: equipmentId,
                  equipement: equipement,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // À partir de 840 px : formulaire et calculs en deux colonnes ;
    // l'assistant s'ouvre dans sa fenêtre, au-dessus.
    final colonnes = [
      Expanded(child: form),
      SizedBox(
        width: kCalculationPanelWidth,
        child: SingleChildScrollView(
          // Sans marge haute : « Calculs » s'aligne sur le premier titre du
          // formulaire.
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TitreSection('Calculs'),
              BlocCalculs(
                calculs: calculs,
                content: content,
                equipement: equipement,
              ),
            ],
          ),
        ),
      ),
    ];

    return EditeurPleinEcran(
      titre: initial == null ? 'Nouvelle recette' : 'Modifier la recette',
      closePath: initial == null
          ? AppRoutes.recipes
          : AppRoutes.recipe(initial.id),
      dirty: _dirty,
      saving: _saving,
      onSave: () => _save(equipmentId),
      abandonMessage:
          'Les changements de cette recette ne seront pas '
          'enregistrés.',
      confirmerDepart: _conversationAPerdre ? _confirmerDepart : null,
      actionsAvant: [
        if (assistantVisible)
          IconButton(
            focusNode: _assistantFocus,
            tooltip: TextesAssistant.ouvrir,
            onPressed: () => _ouvrirAssistant(width),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
      ],
      bottomBar: wide || keyboardOpen
          ? null
          : BarreCalculs(
              calculs: calculs,
              // ticket: /recettes/nouvelle/fenetre/calculs, /recettes/:id/modifier/fenetre/calculs
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: BlocCalculs(
                    calculs: calculs,
                    content: content,
                    equipement: equipement,
                  ),
                ),
              ),
            ),
      body: wide
          ? Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kEditorMaxWidth),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: colonnes,
                ),
              ),
            )
          : form,
    );
  }

  List<Widget> _sections({
    required CalculsRecette calculs,
    required List<Equipment> equipment,
    required String? readerUid,
    required String? equipmentId,
    required EquipementRecette equipement,
  }) {
    final theme = Theme.of(context);
    final volume = lireNombre(_volume.text).valeur;
    final hopIbu = <int, double>{
      if (calculs is CalculsObtenus)
        for (final h in calculs.calculation.hopBitterness) h.hop.index: h.ibu,
    };
    final longer = <int>{
      if (calculs is CalculsObtenus)
        for (final h in calculs.calculation.hopsLongerThanBoil) h.index,
    };
    final fermentableTotal = _fermentables.fold(0.0, (s, f) => s + f.weightG);
    final marques = _marquesAffichees;
    final author = widget.initial?.content.author;
    final ids = {for (final e in equipment) e.id};
    Widget section(_Section s, String title, {String? trailing}) =>
        KeyedSubtree(
          key: _keys[s],
          child: TitreSection(title, trailing: trailing),
        );
    Widget add(String label, VoidCallback onPressed, {String? capMessage}) =>
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: capMessage == null ? onPressed : null,
                icon: const Icon(Icons.add),
                label: Text(label),
              ),
              if (capMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(capMessage, style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        );

    return [
      section(_Section.general, 'Général'),
      KeyedSubtree(
        key: _nameKey,
        child: TextFormField(
          controller: _name,
          focusNode: _nameFocus,
          autofocus: widget.initial == null,
          maxLength: kRecipeNameMaxLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: 'Nom', errorText: _nameError),
          onChanged: (v) => setState(() {
            _dirty = true;
            if (v.trim().isNotEmpty) _nameError = null;
          }),
        ),
      ),
      if (author != null)
        LigneFiche(
          label: 'Auteur indiqué par le fichier importé',
          value: author,
        ),
      const SizedBox(height: 8),
      // Style BJCP choisi dans la Bibliothèque par son code ou son nom
      // (ADR-005, E3) : son nom exact est écrit, l'export BeerXML le retrouve.
      // La saisie libre reste possible. La liste s'ouvre sur un champ vide, et
      // l'icône de fin de champ ouvre « Choisir un style » (ticket #49).
      ChampBibliotheque(
        nature: NatureReferentiel.styles,
        choixDesStyles: true,
        controller: _style,
        focusNode: _styleFocus,
        detail: detailStyle,
        onSelected: _changed,
        fieldBuilder: (context, aide, onSubmitted, boutonListe) => TextFormField(
          controller: _style,
          focusNode: _styleFocus,
          // Entrée choisit la suggestion surlignée après ↑ ou ↓ ; sinon le style
          // tapé reste et le focus passe au champ suivant.
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => onSubmitted(),
          maxLength: kRecipeNameMaxLength,
          decoration: InputDecoration(
            labelText: 'Style (facultatif)',
            helperText: aide ?? styleAide,
            suffixIcon: boutonListe,
            helperMaxLines: 8,
          ),
          onChanged: _changed,
        ),
      ),
      const SizedBox(height: 8),
      ListeBeerJson(
        label: 'Type de recette',
        values: typesRecette,
        selected: _type,
        onChanged: (t) {
          _type = t;
          _changed();
        },
      ),
      const SizedBox(height: 16),
      ChampNombre(
        controller: _volume,
        label: 'Volume en fermenteur (L)',
        minExclu: true,
        avertissement: volume != null && volume > kUnusualVolumeLitres
            ? 'Volume inhabituel : ${formatLitres(volume)}. Vérifiez la saisie.'
            : null,
        onChanged: _changed,
      ),
      const SizedBox(height: 16),
      ChampNombre(
        controller: _boil,
        label: 'Durée d\'ébullition (min)',
        max: 600,
        entier: true,
        onChanged: _changed,
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String?>(
        key: ValueKey('equipement-$equipmentId'),
        initialValue: equipmentId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Équipement'),
        items: [
          const DropdownMenuItem(value: null, child: Text('Aucun équipement')),
          for (final e in equipment)
            DropdownMenuItem(
              value: e.id,
              child: Text(
                e.ownerUid == readerUid
                    ? e.name
                    : '${e.name} (${libelleAuteur(ownerUid: e.ownerUid, ownerName: e.ownerName, readerUid: readerUid)})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (equipmentId != null && !ids.contains(equipmentId))
            DropdownMenuItem(
              value: equipmentId,
              child: Text(libelleEquipement(equipement)),
            ),
        ],
        onChanged: (id) => setState(() {
          _equipmentId = id;
          _equipmentTouched = true;
          _dirty = true;
        }),
      ),
      section(
        _Section.fermentables,
        'Malts et sucres',
        trailing: _fermentables.isEmpty
            ? null
            : '${_fermentables.length} · ${formatKilogrammes(fermentableTotal)}',
      ),
      for (final (i, f) in _fermentables.indexed)
        LigneEditeur(
          title: f.name,
          details: detailsFermentescible(f, fiche: false, marques: marques),
          warning: f.weightG > kUnusualFermentableGrams
              ? quantiteInhabituelle(formatKilogrammes(f.weightG))
              : null,
          onTap: () => _openFermentable(i),
          onDuplicate: () => _duplicateLine(
            _fermentables,
            i,
            kMaxFermentables,
            sort: sortFermentables,
          ),
          onRemove: () =>
              _remove(_fermentables, i, f.name, sort: sortFermentables),
        ),
      add(
        'Ajouter un malt ou un sucre',
        _openFermentable,
        capMessage: _fermentables.length >= kMaxFermentables
            ? '$kMaxFermentables malts et sucres au plus.'
            : null,
      ),
      section(_Section.hops, 'Houblons', trailing: enteteHoublons(_hops)),
      for (final (i, h) in _hops.indexed)
        LigneEditeur(
          title: h.name,
          details: detailsHoublon(
            h,
            fiche: false,
            ibu: hopIbu[i],
            marques: marques,
          ),
          warning: [
            if (_inhabituelle(h.amount, kUnusualHopGrams))
              quantiteInhabituelle(formatQuantiteRecette(h.amount)),
            if (longer.contains(i))
              'Plus long que l\'ébullition de la recette.',
          ].join(' ').nullIfEmpty,
          onTap: () => _openHop(i),
          onDuplicate: () => _duplicateLine(_hops, i, kMaxHops, sort: sortHops),
          onRemove: () => _remove(_hops, i, h.name, sort: sortHops),
        ),
      add(
        'Ajouter un houblon',
        _openHop,
        capMessage: _hops.length >= kMaxHops
            ? '$kMaxHops houblons au plus.'
            : null,
      ),
      section(
        _Section.others,
        'Autres ajouts',
        trailing: _others.isEmpty ? null : '${_others.length}',
      ),
      for (final (i, o) in _others.indexed)
        LigneEditeur(
          title: o.name,
          details: detailsAjout(o),
          warning: _inhabituelle(o.amount, kUnusualOtherGrams)
              ? quantiteInhabituelle(formatQuantiteRecette(o.amount))
              : null,
          onTap: () => _openOther(i),
          onDuplicate: () => _duplicateLine(_others, i, kMaxOthers),
          onRemove: () => _remove(_others, i, o.name),
        ),
      add(
        'Ajouter un ajout',
        _openOther,
        capMessage: _others.length >= kMaxOthers
            ? '$kMaxOthers ajouts au plus.'
            : null,
      ),
      section(_Section.yeast, 'Levure'),
      if (_yeasts.isEmpty)
        add('Ajouter une levure', _openYeast)
      else
        LigneEditeur(
          title: _yeasts.first.name,
          details: detailsLevure(_yeasts.first, fiche: false, marques: marques),
          onTap: _openYeast,
          onRemove: () => _remove(_yeasts, 0, _yeasts.first.name),
        ),
      section(
        _Section.steps,
        'Paliers d\'empâtage',
        trailing: _steps.isEmpty ? null : '${_steps.length}',
      ),
      ChampNombre(
        controller: _grainTemp,
        label: 'Température du grain (°C)',
        aide:
            'Température des malts au moment de l\'empâtage, souvent celle '
            'de la pièce.',
        min: _grainTempMin,
        max: _grainTempMax,
        onChanged: _changed,
      ),
      const SizedBox(height: 8),
      for (final (i, s) in _steps.indexed)
        LigneEditeur(
          title: s.name,
          details: detailsPalier(s),
          onTap: () => _openStep(i),
          onMoveUp: i == 0 ? null : () => _moveStep(i, -1),
          onMoveDown: i == _steps.length - 1 ? null : () => _moveStep(i, 1),
          onDuplicate: () => _duplicateLine(_steps, i, kMaxMashSteps),
          onRemove: () => _remove(_steps, i, s.name),
        ),
      add(
        'Ajouter un palier',
        _openStep,
        capMessage: _steps.length >= kMaxMashSteps
            ? '$kMaxMashSteps paliers au plus.'
            : null,
      ),
      section(_Section.notes, 'Notes'),
      TextFormField(
        controller: _aroma,
        maxLength: kRecipeAromaMaxLength,
        minLines: 2,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: RecipeEditorScreen.aromaLabel,
          helperText: RecipeEditorScreen.aromaAide,
          helperMaxLines: 3,
        ),
        // Les règles comptent des unités UTF-16 (`String.length`), le compteur
        // du champ des graphèmes : un émoji y compte pour un, et pour deux ou
        // plus dans les règles. Refus avant l'écriture.
        validator: (v) => (v ?? '').trim().length > kRecipeAromaMaxLength
            ? RecipeEditorScreen.aromaTropLongue
            : null,
        onChanged: _changed,
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: _notes,
        maxLength: kRecipeNotesMaxLength,
        minLines: 3,
        maxLines: 10,
        decoration: const InputDecoration(labelText: 'Notes (facultatif)'),
        onChanged: _changed,
      ),
    ];
  }

  /// Quantité au-delà de [thresholdGrams] grammes, ou de [kUnusualLineLitres]
  /// litres (U6).
  static bool _inhabituelle(Quantite q, double thresholdGrams) =>
      q.valeur > (q.enLitres ? kUnusualLineLitres : thresholdGrams);
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// Puces de saut vers chaque section, avec le nombre de lignes.
class _JumpChips extends StatelessWidget {
  const _JumpChips({required this.counts, required this.onJump});

  final Map<_Section, int> counts;
  final ValueChanged<_Section> onJump;

  @override
  Widget build(BuildContext context) {
    String label(_Section s) => switch (s) {
      _Section.general => 'Général',
      _Section.fermentables => 'Malts et sucres (${counts[s]})',
      _Section.hops => 'Houblons (${counts[s]})',
      _Section.others => 'Autres ajouts (${counts[s]})',
      _Section.yeast => 'Levure (${counts[s]})',
      _Section.steps => 'Paliers (${counts[s]})',
      _Section.notes => 'Notes',
    };
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            for (final s in _Section.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ActionChip(
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  label: Text(label(s)),
                  onPressed: () => onJump(s),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
