import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/referentiel.dart';
import 'choix_style.dart';

/// Nombre de suggestions affichées sous le champ.
const kMaxSuggestions = 8;

/// Aide du champ quand les suggestions ne peuvent pas être lues (panne,
/// absentes du cache hors ligne, illisibles).
const kSuggestionsIndisponibles =
    'Suggestions de la Bibliothèque indisponibles. Vous pouvez saisir le nom.';

/// Aide du champ quand l'index est absent du serveur : la Bibliothèque n'est
/// pas encore remplie.
const kBibliothequeVide = 'Bibliothèque vide : suggestions indisponibles.';

/// Nom de la liste des suggestions, lu par le lecteur d'écran.
const kSuggestionsLibelle = 'Suggestions de la Bibliothèque';

/// « 3 suggestions de la Bibliothèque », annoncé quand la liste change.
String nombreSuggestions(int n) => n == 1
    ? '1 suggestion de la Bibliothèque'
    : '$n suggestions de la Bibliothèque';

/// Entrées de [entrees] qui correspondent à [texte] (nom, alias, code de
/// style, producteur), celles dont le nom commence par le texte en tête,
/// [kMaxSuggestions] au plus. Pour un texte vide : rien, ou, avec
/// [stylesSiVide], les premiers styles dans l'ordre des codes BJCP.
List<EntreeIndex> suggestionsPour(
  List<EntreeIndex> entrees,
  String texte, {
  bool stylesSiVide = false,
}) {
  final requete = normaliserRecherche(texte.trim());
  if (requete.isEmpty) {
    return stylesSiVide
        ? stylesParCode(entrees).take(kMaxSuggestions).toList()
        : const [];
  }
  final debut = <EntreeIndex>[];
  final ailleurs = <EntreeIndex>[];
  for (final e in entrees) {
    if (!e.correspond(requete)) continue;
    (normaliserRecherche(e.name).startsWith(requete) ? debut : ailleurs).add(e);
  }
  return [...debut, ...ailleurs].take(kMaxSuggestions).toList();
}

/// Seconde ligne d'une suggestion de style : « 21A · IPA ».
String? detailStyle(EntreeIndex e) =>
    e is EntreeStyle ? [e.code, ?e.category].join(' · ') : null;

/// Champ de texte qui propose des entrées de `beer_index/{nature}` (ADR-005,
/// E2 et E3). L'index est lu à la première prise du focus, par `get()`
/// mémorisé par le dépôt de données ; hors ligne, dans le cache seul. Sans
/// index, le champ reste en saisie libre et relit à la prise du focus
/// suivante. Choisir une suggestion écrit son nom dans [controller], puis
/// appelle [onSelected]. Entrée ou « Suivant » ne choisit la suggestion
/// surlignée qu'après un déplacement par ↑ ou ↓ ; sinon le nom tapé reste et
/// le focus passe au champ suivant. La liste s'ouvre du côté où il y a le plus
/// de place.
///
/// [choixDesStyles], réservé au champ « Style » ([NatureReferentiel.styles]) :
/// l'index est lu dès l'ouverture du champ, sans attendre le focus ; la liste
/// s'ouvre aussi sur un champ vide ; l'aide dit si le texte est un style de la
/// Bibliothèque ([aideStyleSaisi]) ; `fieldBuilder` reçoit l'icône qui ouvre
/// « Choisir un style », désactivée sans index.
class ChampBibliotheque extends ConsumerStatefulWidget {
  const ChampBibliotheque({
    super.key,
    required this.nature,
    required this.controller,
    required this.focusNode,
    required this.onSelected,
    required this.fieldBuilder,
    this.detail,
    this.choixDesStyles = false,
  }) : assert(!choixDesStyles || nature == NatureReferentiel.styles);

  final NatureReferentiel nature;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<EntreeIndex> onSelected;

  /// Construit le champ de texte, avec [controller] et [focusNode] ; [aide] :
  /// texte d'aide quand les suggestions sont indisponibles ; [onSubmitted] :
  /// à appeler par `onFieldSubmitted` ; [boutonListe] : icône « Liste des
  /// styles » (`suffixIcon`), `null` sans [choixDesStyles].
  final Widget Function(
    BuildContext context,
    String? aide,
    VoidCallback onSubmitted,
    Widget? boutonListe,
  )
  fieldBuilder;

  /// Seconde ligne d'une suggestion (code, valeurs), ou `null`.
  final String? Function(EntreeIndex entree)? detail;

  /// Champ « Style » : liste ouverte sur un champ vide, aide du style saisi,
  /// icône « Liste des styles ».
  final bool choixDesStyles;

  @override
  ConsumerState<ChampBibliotheque> createState() => _ChampBibliothequeState();
}

class _ChampBibliothequeState extends ConsumerState<ChampBibliotheque> {
  List<EntreeIndex> _entrees = const [];
  bool _lecture = false;

  /// Vrai quand l'index est lu (`DocumentTrouve`).
  bool _indexLu = false;

  /// Lecture en cours, attendue par la feuille « Choisir un style ».
  Future<void>? _enCours;

  /// Aide affichée sous le champ : [kSuggestionsIndisponibles],
  /// [kBibliothequeVide], ou `null` quand l'index est lu.
  String? _aide;

  /// Vrai après ↑ ou ↓ dans la liste ouverte : Entrée choisit alors l'option
  /// surlignée. Remis à faux à chaque frappe et à chaque choix.
  bool _deplace = false;

  /// Texte à l'ouverture du champ (ligne modifiée) : sans frappe, la liste ne
  /// s'ouvre pas à l'arrivée de l'index.
  late final String _texteInitial;
  late String _dernierTexte;

  @override
  void initState() {
    super.initState();
    _texteInitial = widget.controller.text;
    _dernierTexte = _texteInitial;
    widget.focusNode.addListener(_surFocus);
    widget.controller.addListener(_surTexte);
    // Champ ouvert avec le focus (`autofocus`) : la lecture part aussitôt.
    // Champ « Style » : elle part toujours, pour que l'aide dise dès
    // l'ouverture si le style d'une recette existante est hors Bibliothèque.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.choixDesStyles) {
        _demarrerLecture();
      } else {
        _surFocus();
      }
    });
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_surFocus);
    widget.controller.removeListener(_surTexte);
    super.dispose();
  }

  void _surTexte() {
    final texte = widget.controller.text;
    if (texte == _dernierTexte) return;
    _dernierTexte = texte;
    _deplace = false;
    // L'aide du champ « Style » suit le texte.
    if (widget.choixDesStyles && _indexLu && mounted) setState(() {});
  }

  void _surFocus() {
    // L'aide du champ « Style » dépend du focus (voir [_aideAffichee]).
    if (widget.choixDesStyles && mounted) setState(() {});
    if (!widget.focusNode.hasFocus) return;
    _demarrerLecture();
  }

  /// Lance la lecture de l'index, sauf si elle est faite ou en cours.
  void _demarrerLecture() {
    if (_lecture) return;
    _lecture = true;
    final lecture = _lire();
    _enCours = lecture;
    unawaited(lecture.whenComplete(() => _enCours = null));
  }

  /// Lit l'index par `get()` : du serveur en ligne, du cache seul hors ligne.
  /// Sans index (absent, absent du cache, illisible, panne), la prochaine
  /// prise du focus relit.
  Future<void> _lire() async {
    final offline = ref.read(grantedAccessProvider)?.offline ?? false;
    final RechercheDocument<IndexReferentiel> lu;
    try {
      lu = await ref
          .read(libraryRepositoryProvider)
          .lireIndex(widget.nature, cacheSeul: offline);
    } catch (_) {
      // Déjà rapportée par le dépôt de données : `lireIndex` rapporte chaque
      // panne avant de la relancer. Le champ dit que les suggestions sont
      // indisponibles.
      _lecture = false;
      if (mounted) setState(() => _aide = kSuggestionsIndisponibles);
      return;
    }
    if (!mounted) return;
    final (entrees, aide) = switch (lu) {
      DocumentTrouve(:final value) => (value.entrees, null),
      // Absent du serveur : la Bibliothèque n'est pas encore remplie.
      DocumentAbsent() => (null, kBibliothequeVide),
      // Absent du cache hors ligne, ou illisible (déjà rapporté).
      _ => (null, kSuggestionsIndisponibles),
    };
    if (entrees == null) _lecture = false;
    setState(() {
      _entrees = entrees ?? const [];
      _indexLu = entrees != null;
      _aide = aide;
    });
    if (entrees != null) _recalculer();
  }

  /// Index arrivé après une frappe : `RawAutocomplete` ne recalcule ses options
  /// qu'à un changement du texte. Le texte change d'un caractère puis revient,
  /// curseur compris, et la liste suit l'index sans attendre la touche
  /// suivante.
  void _recalculer() {
    final controller = widget.controller;
    final valeur = controller.value;
    if (!widget.focusNode.hasFocus) return;
    // Champ « Style » vide : la liste s'ouvre sur les premiers styles.
    final vide = valeur.text.trim().isEmpty;
    if (vide ? !widget.choixDesStyles : valeur.text == _texteInitial) return;
    final deplace = _deplace;
    controller.value = valeur.copyWith(text: '${valeur.text} ');
    controller.value = valeur;
    _deplace = deplace;
  }

  /// ↑ et ↓ déplacent la surbrillance (gérés par `RawAutocomplete`) : ils
  /// sont seulement notés ici.
  KeyEventResult _surTouche(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.arrowUp)) {
      _deplace = true;
    }
    return KeyEventResult.ignored;
  }

  /// Ouvre « Choisir un style ». Le focus quitte le champ avant l'ouverture :
  /// au retour, la liste des suggestions ne s'ouvre pas sur le style choisi.
  /// L'index déjà lu s'affiche aussitôt ; sinon la feuille attend sa lecture.
  Future<void> _ouvrirListe() async {
    widget.focusNode.unfocus();
    final choix = await choisirStyle(context, lire: _indexPourFeuille);
    if (choix == null || !mounted) return;
    _deplace = false;
    widget.controller.value = TextEditingValue(
      text: choix.name,
      selection: TextSelection.collapsed(offset: choix.name.length),
    );
    widget.onSelected(choix);
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        styleChoisi(choix.name),
        Directionality.of(context),
      ),
    );
  }

  /// Index pour la feuille : lance la lecture si elle n'est ni faite ni en
  /// cours (premier appel, ou « Réessayer » après une panne), puis rend
  /// l'index lu, ou rien avec la raison.
  Future<IndexStyles> _indexPourFeuille() async {
    _demarrerLecture();
    await _enCours;
    return (
      entrees: _indexLu ? _entrees : null,
      vide: _aide == kBibliothequeVide,
    );
  }

  /// Aide affichée sous le champ : panne ou Bibliothèque vide d'abord, puis,
  /// pour le champ « Style », l'aide du style saisi. Pendant la frappe, un
  /// texte qui a encore des suggestions n'affiche pas « hors Bibliothèque » :
  /// l'avertissement attend la sortie du champ.
  String? get _aideAffichee {
    final aide = _aide;
    if (aide != null || !widget.choixDesStyles || !_indexLu) return aide;
    final texte = widget.controller.text;
    final style = aideStyleSaisi(_entrees, texte);
    if (style == kStyleHorsBibliotheque &&
        widget.focusNode.hasFocus &&
        suggestionsPour(_entrees, texte).isNotEmpty) {
      return null;
    }
    return style;
  }

  @override
  Widget build(BuildContext context) {
    final boutonListe = widget.choixDesStyles
        ? IconButton(
            icon: const Icon(Icons.list),
            tooltip: kListeStylesLibelle,
            // Sans index (absent, panne, hors ligne sans cache) : désactivée ;
            // la prochaine prise du focus relit l'index.
            onPressed: _aide == null ? () => unawaited(_ouvrirListe()) : null,
          )
        : null;
    return RawAutocomplete<EntreeIndex>(
      textEditingController: widget.controller,
      focusNode: widget.focusNode,
      optionsViewOpenDirection: OptionsViewOpenDirection.mostSpace,
      displayStringForOption: (e) => e.name,
      optionsBuilder: (value) => suggestionsPour(
        _entrees,
        value.text,
        stylesSiVide: widget.choixDesStyles,
      ),
      onSelected: (e) {
        _deplace = false;
        widget.onSelected(e);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _surTouche,
        child: widget.fieldBuilder(context, _aideAffichee, () {
          // Sans déplacement par ↑ ou ↓, le nom tapé reste : l'action du
          // clavier (« Suivant ») fait passer le focus au champ suivant.
          if (_deplace) onSubmitted();
        }, boutonListe),
      ),
      optionsViewBuilder: (context, onSelected, options) => _Suggestions(
        options: options.toList(),
        onSelected: onSelected,
        detail: widget.detail,
      ),
    );
  }
}

/// Liste des suggestions, à la largeur du champ, [kSuggestionsMaxHeight] au
/// plus, sous la ligne du nombre de suggestions. Le lecteur d'écran la nomme
/// et annonce leur nombre ; l'option surlignée au clavier a le fond de focus
/// du thème, sans état « sélectionné », et défile dans la vue : en bas de la
/// vue en descendant, en haut en montant.
class _Suggestions extends StatefulWidget {
  const _Suggestions({
    required this.options,
    required this.onSelected,
    required this.detail,
  });

  final List<EntreeIndex> options;
  final ValueChanged<EntreeIndex> onSelected;
  final String? Function(EntreeIndex)? detail;

  @override
  State<_Suggestions> createState() => _SuggestionsState();
}

class _SuggestionsState extends State<_Suggestions> {
  final _cles = <int, GlobalKey>{};
  int? _surligne;

  void _montrer(int index, {required bool descente}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cible = _cles[index]?.currentContext;
      if (!mounted || cible == null) return;
      unawaited(
        Scrollable.ensureVisible(
          cible,
          alignmentPolicy: descente
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surligne = AutocompleteHighlightedOption.of(context);
    final avant = _surligne;
    if (avant != null && avant != surligne) {
      _montrer(surligne, descente: surligne > avant);
    }
    _surligne = surligne;
    final options = widget.options;
    return Semantics(
      container: true,
      label: kSuggestionsLibelle,
      child: Material(
        elevation: 4,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: kSuggestionsMaxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    nombreSuggestions(options.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, i) {
                    final e = options[i];
                    final sous = widget.detail?.call(e);
                    return ListTile(
                      key: _cles.putIfAbsent(i, GlobalKey.new),
                      // Fond de focus du thème, sans l'état « sélectionné »
                      // qu'un lecteur d'écran annoncerait.
                      tileColor: i == surligne ? theme.focusColor : null,
                      title: Text(e.name),
                      subtitle: sous == null ? null : Text(sous),
                      onTap: () => widget.onSelected(e),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
