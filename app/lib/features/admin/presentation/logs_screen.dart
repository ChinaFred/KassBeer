import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../domain/log_entry.dart';

/// Admin › Journaux (ADR-011, J2) : sortie des Cloud Functions, lue par la
/// callable `queryLogs`. La recherche part sur « Rechercher » seul, jamais à
/// l'ouverture ni sur une frappe (P50). Le menu « Fonction » vient de la liste
/// rendue par le serveur.
class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  static const titre = 'Journaux';
  static const sousTitre = 'Messages des fonctions du serveur';
  static const invite = 'Choisissez les filtres, puis appuyez sur Rechercher.';
  static const rechercher = 'Rechercher';
  static const rechercheEnCours = 'Recherche en cours';
  static const chargement = 'Recherche des journaux';
  static const vide =
      'Aucune entrée pour ces filtres. Élargissez la période ou videz un '
      'champ, puis relancez la recherche.';
  static const fin = 'Fin des journaux pour cette période.';
  static const chargerSuite = 'Charger la suite';
  static const filtresModifies =
      'Filtres modifiés : appuyez sur Rechercher pour mettre la liste à jour.';
  static const modifierFiltres = 'Modifier les filtres';
  static const noteEmails =
      'Les journaux peuvent contenir des adresses e-mail. Ne les recopiez pas '
      'dans une Issue.';
  static const gravite = 'Gravité';
  static const periode = 'Période';
  static const fonction = 'Fonction';
  static const ticket = 'Ticket';
  static const texte = 'Texte à chercher';
  static const aideTicket = 'Identifiant du ticket';
  static const aideTexte = 'Mot ou expression contenu dans le message';
  static const aideFonctions =
      'La liste des fonctions arrive avec la première recherche.';
  static const message = 'Message';
  static const donnees = 'Données';
  static const copier = 'Copier l\'entrée';
  static const copie = 'Entrée copiée.';
  static const copieImpossible = 'Impossible de copier l\'entrée.';
  static const plusDeFiltres = 'Plus de filtres';

  /// « Plus de filtres », suivi du nombre de filtres remplis parmi
  /// « Fonction », « Ticket » et « Texte à chercher » : « Plus de filtres (2) ».
  static String plusDeFiltresCompte(int n) =>
      n == 0 ? plusDeFiltres : '$plusDeFiltres ($n)';

  /// « Gravité : Info et plus », libellé de la puce de menu.
  static String puce(String filtre, String valeur) => '$filtre : $valeur';

  /// « Texte coupé à 8 000 caractères. », [gardes] rendu par le serveur.
  static String texteCoupe(int gardes) =>
      'Texte coupé à ${formatNombre(gardes.toDouble(), decimales: 0)} '
      'caractères.';

  /// « 1 entrée affichée », « 12 entrées affichées ».
  static String compte(int n) =>
      n <= 1 ? '$n entrée affichée' : '$n entrées affichées';

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

/// Bouton qui a lancé l'appel en cours : lui seul montre l'attente.
enum _Origine { rechercher, reessayer, suite }

class _LogsScreenState extends ConsumerState<LogsScreen> {
  var _filtres = const FiltresJournaux();

  /// Filtres de la liste affichée ; `null` avant la première réponse.
  FiltresJournaux? _filtresListe;
  final _entrees = <EntreeJournal>[];

  /// Rangs des entrées dépliées, gardés au défilement ; vidés par une
  /// nouvelle recherche.
  final _ouvertes = <int>{};

  /// Numéro de la première page affichée, monté à chaque nouvelle recherche.
  int _recherche = 0;
  String? _suite;

  /// Noms rendus par le serveur ; `null` avant la première réponse.
  List<String>? _fonctions;

  /// Origine de l'appel en cours ; `null` sans appel.
  _Origine? _origine;
  bool get _chargement => _origine != null;

  /// Panne affichée : elle reste jusqu'à la réponse de l'appel suivant.
  EchecJournaux? _echec;

  /// Dernier appel, rejoué par « Réessayer ».
  ({FiltresJournaux filtres, String? suite})? _dernierAppel;

  /// Téléphone : bloc des filtres replié en une ligne après une recherche.
  bool _replie = false;

  /// « Fonction », « Ticket » et « Texte à chercher » affichés. Repliés par
  /// défaut sur téléphone, toujours affichés sur grand écran.
  bool _plusDeFiltres = false;

  String? _erreurTicket;
  String? _erreurTexte;

  /// Numéro du dernier appel : une réponse plus ancienne est ignorée.
  int _appel = 0;

  final _ticket = TextEditingController();
  final _texte = TextEditingController();
  final _focusTicket = FocusNode();
  final _focusTexte = FocusNode();

  @override
  void dispose() {
    _ticket.dispose();
    _texte.dispose();
    _focusTicket.dispose();
    _focusTexte.dispose();
    super.dispose();
  }

  bool get _listeLue => _filtresListe != null;
  bool get _filtresModifies => _listeLue && _filtres != _filtresListe;

  void _changer(FiltresJournaux filtres) => setState(() => _filtres = filtres);

  Future<void> _lancer(
    FiltresJournaux filtres, {
    String? suite,
    required _Origine origine,
  }) async {
    final appel = ++_appel;
    _dernierAppel = (filtres: filtres, suite: suite);
    setState(() {
      _origine = origine;
      _erreurTicket = null;
      _erreurTexte = null;
    });
    final PageJournaux page;
    try {
      page = await ref
          .read(logsRepositoryProvider)
          .rechercher(filtres, suite: suite);
    } on EchecJournaux catch (echec) {
      // Déjà rapporté par le dépôt de données : l'écran affiche la panne.
      if (!mounted || appel != _appel) return;
      final surChamp = echec.cause == CauseEchecJournaux.champ;
      setState(() {
        _origine = null;
        if (!surChamp) {
          _echec = echec;
        } else {
          // Le refus vise un champ : plus aucune panne générale affichée.
          _echec = null;
          _replie = false;
          _plusDeFiltres = true;
          // Message du serveur ; aucune borne recopiée en Dart.
          final texte = echec.motif ?? echec.cause.message;
          if (echec.champ == EchecJournaux.champTicket) {
            _erreurTicket = texte;
          } else {
            _erreurTexte = texte;
          }
        }
      });
      if (surChamp) {
        (echec.champ == EchecJournaux.champTicket ? _focusTicket : _focusTexte)
            .requestFocus();
      }
      return;
    }
    if (!mounted || appel != _appel) return;
    setState(() {
      if (suite == null) {
        _entrees
          ..clear()
          ..addAll(page.entrees);
        _ouvertes.clear();
        _recherche++;
        _filtresListe = filtres;
        _replie = true;
      } else {
        _entrees.addAll(page.entrees);
      }
      _suite = page.suite;
      _fonctions = page.fonctions;
      _echec = null;
      _origine = null;
    });
  }

  void _rechercher() =>
      unawaited(_lancer(_filtres, origine: _Origine.rechercher));

  void _chargerLaSuite() => unawaited(
    _lancer(_filtresListe!, suite: _suite, origine: _Origine.suite),
  );

  void _reessayer() {
    final dernier = _dernierAppel;
    if (dernier == null) return;
    // Page suivante refusée (trop ancienne) : la rejouer échouerait encore,
    // la première page est relue avec les filtres de la liste.
    if (_echec?.cause == CauseEchecJournaux.refuse) {
      unawaited(
        _lancer(_filtresListe ?? dernier.filtres, origine: _Origine.reessayer),
      );
      return;
    }
    unawaited(
      _lancer(
        dernier.filtres,
        suite: dernier.suite,
        origine: _Origine.reessayer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final large =
        WindowSize.of(MediaQuery.sizeOf(context).width) == WindowSize.expanded;
    final echec = _echec;
    final reessayer = echec != null && echec.cause.reessayable
        ? _reessayer
        : null;

    final note = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Text(
        LogsScreen.noteEmails,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    final head = <Widget>[
      if (!large && _replie && _listeLue)
        _resumeFiltres(theme)
      else
        _blocFiltres(theme, large: large),
    ];

    if (!_listeLue || (_entrees.isEmpty && echec != null)) {
      head.addAll([const SizedBox(height: 8), note]);
      head.add(
        echec != null
            ? EtatErreur(
                message: echec.cause.message,
                retrying: _origine == _Origine.reessayer,
                retryEnabled: !_chargement,
                retryingLabel: LogsScreen.rechercheEnCours,
                onRetry: reessayer,
              )
            : _origine == _Origine.rechercher
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: EtatChargement(label: LogsScreen.chargement),
              )
            : const EtatVide(icon: Icons.search, message: LogsScreen.invite),
      );
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: head,
      );
    }

    head.addAll([
      if (echec != null)
        BandeauListePerimee(
          message: echec.cause.message,
          retrying: _origine == _Origine.reessayer,
          retryEnabled: !_chargement,
          retryingLabel: LogsScreen.rechercheEnCours,
          onRetry: reessayer,
        ),
      if (_filtresModifies)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Semantics(
            liveRegion: true,
            child: Text(
              LogsScreen.filtresModifies,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
        child: Semantics(
          liveRegion: true,
          child: Text(
            LogsScreen.compte(_entrees.length),
            style: theme.textTheme.titleSmall,
          ),
        ),
      ),
      note,
      if (_entrees.isEmpty)
        const EtatVide(icon: Icons.inbox_outlined, message: LogsScreen.vide),
    ]);

    final foot = <Widget>[
      if (_entrees.isNotEmpty && echec == null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _suite == null
                ? Text(
                    LogsScreen.fin,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : _filtresModifies
                ? const SizedBox.shrink()
                : OutlinedButton(
                    onPressed: _chargement ? null : _chargerLaSuite,
                    child: _origine == _Origine.suite
                        ? const IndicateurBouton(
                            label: LogsScreen.rechercheEnCours,
                          )
                        : const Text(LogsScreen.chargerSuite),
                  ),
          ),
        ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: head.length + _entrees.length + foot.length,
      itemBuilder: (context, i) {
        if (i < head.length) return head[i];
        final j = i - head.length;
        if (j >= _entrees.length) return foot[j - _entrees.length];
        final entree = _entrees[j];
        return _LigneJournal(
          // Le numéro de recherche change la clé : une nouvelle recherche
          // replie tout, même pour une entrée revenue au même rang.
          key: ValueKey('journal-$_recherche-${entree.insertId}-$j'),
          entree: entree,
          ouverte: _ouvertes.contains(j),
          onOuverte: (ouverte) =>
              ouverte ? _ouvertes.add(j) : _ouvertes.remove(j),
        );
      },
    );
  }

  /// Téléphone, après une recherche : une ligne et « Modifier les filtres ».
  Widget _resumeFiltres(ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(_filtres.resume, style: theme.textTheme.bodyMedium),
        TextButton.icon(
          onPressed: () => setState(() => _replie = false),
          icon: const Icon(Icons.tune),
          label: const Text(LogsScreen.modifierFiltres),
        ),
      ],
    ),
  );

  /// Nombre de filtres remplis parmi « Fonction », « Ticket » et « Texte ».
  int get _filtresEnPlus => [
    _filtres.fonction != null,
    _filtres.ticket.trim().isNotEmpty,
    _filtres.texte.isNotEmpty,
  ].where((rempli) => rempli).length;

  Widget _blocFiltres(ThemeData theme, {required bool large}) {
    final gravite = _PuceMenu<FiltreGravite>(
      filtre: LogsScreen.gravite,
      valeurs: FiltreGravite.values,
      libelleDe: (g) => g.libelle,
      choisie: _filtres.gravite,
      onChoisie: (g) => _changer(_filtres.copyWith(gravite: g)),
    );
    final periode = _PuceMenu<FiltrePeriode>(
      filtre: LogsScreen.periode,
      valeurs: FiltrePeriode.values,
      libelleDe: (p) => p.libelle,
      choisie: _filtres.periode,
      onChoisie: (p) => _changer(_filtres.copyWith(periode: p)),
    );
    // Désactivé pendant tout appel ; l'attente ne s'affiche que s'il l'a lancé.
    final Widget bouton = _origine == _Origine.rechercher
        ? const FilledButton(
            onPressed: null,
            child: IndicateurBouton(label: LogsScreen.rechercheEnCours),
          )
        : FilledButton.icon(
            onPressed: _chargement ? null : _rechercher,
            icon: const Icon(Icons.search),
            label: const Text(LogsScreen.rechercher),
          );

    if (!large) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [gravite, periode, bouton],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: MergeSemantics(
                child: Semantics(
                  expanded: _plusDeFiltres,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _plusDeFiltres = !_plusDeFiltres),
                    icon: Icon(_plusDeFiltres ? Icons.expand_less : Icons.tune),
                    label: Text(LogsScreen.plusDeFiltresCompte(_filtresEnPlus)),
                  ),
                ),
              ),
            ),
            if (_plusDeFiltres) ...[
              const SizedBox(height: 4),
              _menuFonction(null),
              const SizedBox(height: 16),
              _champTicket(),
              const SizedBox(height: 16),
              _champTexte(),
              const SizedBox(height: 8),
            ],
          ],
        ),
      );
    }

    final echelle = MediaQuery.textScalerOf(context).scale(1);
    final largeurChamp = 280 * echelle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [gravite, periode]),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _menuFonction(largeurChamp),
              SizedBox(width: largeurChamp, child: _champTicket()),
              SizedBox(width: largeurChamp, child: _champTexte()),
            ],
          ),
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerRight, child: bouton),
        ],
      ),
    );
  }

  /// Menu des fonctions, tiré de la liste rendue par le serveur (P50).
  Widget _menuFonction(double? largeur) {
    final fonctions = _fonctions;
    return DropdownMenu<String>(
      // Reconstruit quand la liste arrive : les entrées changent.
      key: ValueKey(fonctions?.length ?? -1),
      width: largeur,
      expandedInsets: largeur == null ? EdgeInsets.zero : null,
      label: const Text(LogsScreen.fonction),
      helperText: fonctions == null ? LogsScreen.aideFonctions : null,
      requestFocusOnTap: false,
      initialSelection: _filtres.fonction ?? '',
      dropdownMenuEntries: [
        const DropdownMenuEntry(
          value: '',
          label: FiltresJournaux.toutesLesFonctions,
        ),
        for (final f in fonctions ?? const <String>[])
          DropdownMenuEntry(value: f, label: f),
      ],
      onSelected: (valeur) => _changer(
        _filtres.copyWith(
          fonction: () => valeur == null || valeur.isEmpty ? null : valeur,
        ),
      ),
    );
  }

  Widget _champTicket() => TextField(
    controller: _ticket,
    focusNode: _focusTicket,
    decoration: InputDecoration(
      labelText: LogsScreen.ticket,
      helperText: LogsScreen.aideTicket,
      errorText: _erreurTicket,
    ),
    textInputAction: TextInputAction.done,
    onChanged: (v) {
      _erreurTicket = null;
      _changer(_filtres.copyWith(ticket: v));
    },
  );

  Widget _champTexte() => TextField(
    controller: _texte,
    focusNode: _focusTexte,
    decoration: InputDecoration(
      labelText: LogsScreen.texte,
      helperText: LogsScreen.aideTexte,
      helperMaxLines: 2,
      errorText: _erreurTexte,
      errorMaxLines: 2,
    ),
    textInputAction: TextInputAction.done,
    onChanged: (v) {
      _erreurTexte = null;
      _changer(_filtres.copyWith(texte: v));
    },
  );
}

/// Une entrée : repliée sur son message, dépliée sur ses données.
class _LigneJournal extends ConsumerWidget {
  const _LigneJournal({
    super.key,
    required this.entree,
    required this.ouverte,
    required this.onOuverte,
  });

  final EntreeJournal entree;

  /// Dépliée : l'état vit dans l'écran, une ligne reconstruite après un
  /// défilement le retrouve.
  final bool ouverte;
  final ValueChanged<bool> onOuverte;

  Future<void> _copier(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final errors = ref.read(errorReportServiceProvider);
    var texte = LogsScreen.copie;
    try {
      await Clipboard.setData(ClipboardData(text: entree.texteCopie));
    } catch (error, stackTrace) {
      // Aucun texte de journal dans le contexte (P13).
      errors.reportError(
        feature: 'admin.logs.copy',
        error: error,
        stackTrace: stackTrace,
      );
      texte = LogsScreen.copieImpossible;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(texte)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Texte agrandi : la date et la fonction passent sous l'étiquette, en
    // entier.
    final grandTexte =
        MediaQuery.textScalerOf(context).scale(1) > kGrandTexteMinScale;
    final date = Text(
      entree.resume,
      maxLines: grandTexte ? null : 1,
      overflow: grandTexte ? null : TextOverflow.ellipsis,
      textAlign: grandTexte ? TextAlign.start : TextAlign.end,
      style: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
    final bordure = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return Card.outlined(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: ouverte,
        onExpansionChanged: onOuverte,
        shape: bordure,
        collapsedShape: bordure,
        dense: true,
        visualDensity: VisualDensity.compact,
        tilePadding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (grandTexte) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: _etiquetteGravite(entree.gravite),
              ),
              const SizedBox(height: 4),
              date,
            ] else
              Row(
                children: [
                  Flexible(child: _etiquetteGravite(entree.gravite)),
                  const SizedBox(width: 8),
                  Expanded(child: date),
                ],
              ),
            const SizedBox(height: 2),
            Text(
              entree.titre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        children: [
          _Section(
            titre: LogsScreen.message,
            contenu: entree.messageComplet,
            // Une pile d'appels se lit en chasse fixe, comme « Données ».
            monospace: entree.messageMultiligne,
          ),
          if (entree.messageCoupe) _NoteCoupe(gardes: entree.caracteresGardes),
          if (entree.payload.isNotEmpty)
            _Section(
              titre: LogsScreen.donnees,
              contenu: entree.payload,
              monospace: true,
            ),
          if (entree.payloadCoupe) _NoteCoupe(gardes: entree.caracteresGardes),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => unawaited(_copier(context, ref)),
              icon: const Icon(Icons.copy),
              label: const Text(LogsScreen.copier),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gravité d'une entrée : icône et mot, sur le fond du ton de l'étiquette.
Etiquette _etiquetteGravite(GraviteJournal gravite) {
  final (icone, ton) = switch (gravite) {
    GraviteJournal.erreur => (Icons.error_outline, TonEtiquette.erreur),
    GraviteJournal.avertissement => (
      Icons.warning_amber_outlined,
      TonEtiquette.tertiaire,
    ),
    GraviteJournal.information => (Icons.info_outline, TonEtiquette.primaire),
    GraviteJournal.debogage => (Icons.bug_report_outlined, TonEtiquette.neutre),
    GraviteJournal.autre => (Icons.circle_outlined, TonEtiquette.neutre),
  };
  return Etiquette(label: gravite.mot, icon: icone, ton: ton);
}

/// Puce « Filtre : valeur » qui ouvre le menu des valeurs du filtre.
class _PuceMenu<T> extends StatefulWidget {
  const _PuceMenu({
    required this.filtre,
    required this.valeurs,
    required this.libelleDe,
    required this.choisie,
    required this.onChoisie,
  });

  final String filtre;
  final List<T> valeurs;
  final String Function(T) libelleDe;
  final T choisie;
  final ValueChanged<T> onChoisie;

  @override
  State<_PuceMenu<T>> createState() => _PuceMenuState<T>();
}

class _PuceMenuState<T> extends State<_PuceMenu<T>> {
  /// Focus de la puce, rendu par le menu à sa fermeture (clavier, web).
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    // ticket: aucun (menu d'un filtre, dans l'écran entier)
    return MenuAnchor(
      childFocusNode: _focus,
      menuChildren: [
        for (final v in w.valeurs)
          MergeSemantics(
            child: Semantics(
              selected: v == w.choisie,
              child: MenuItemButton(
                // Une coche devant la valeur choisie, un vide de même largeur
                // devant les autres.
                leadingIcon: v == w.choisie
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                onPressed: () => w.onChoisie(v),
                child: Text(w.libelleDe(v)),
              ),
            ),
          ),
      ],
      builder: (context, menu, _) => MergeSemantics(
        child: Semantics(
          expanded: menu.isOpen,
          child: ActionChip(
            focusNode: _focus,
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    LogsScreen.puce(w.filtre, w.libelleDe(w.choisie)),
                  ),
                ),
                const ExcludeSemantics(
                  child: Icon(Icons.arrow_drop_down, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// « Texte coupé à N caractères. », N rendu par le serveur.
class _NoteCoupe extends StatelessWidget {
  const _NoteCoupe({required this.gardes});

  final int gardes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        LogsScreen.texteCoupe(gardes),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.titre,
    required this.contenu,
    this.monospace = false,
  });

  final String titre;
  final String contenu;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          if (monospace)
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  contenu,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            )
          else
            SelectableText(contenu, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
