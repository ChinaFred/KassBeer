import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/segments.dart';
import '../../../core/providers.dart';
import '../domain/log_entry.dart';

/// Admin › Journaux (ADR-011, J2) : sortie des Cloud Functions, lue par la
/// callable `queryLogs`. La recherche part sur « Rechercher » seul, jamais à
/// l'ouverture ni sur une frappe (P49). Le menu « Fonction » vient de la liste
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

    final head = <Widget>[
      if (!large && _replie && _listeLue)
        _resumeFiltres(theme)
      else
        _blocFiltres(theme, large: large),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(
          LogsScreen.noteEmails,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ];

    if (!_listeLue || (_entrees.isEmpty && echec != null)) {
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Semantics(
          liveRegion: true,
          child: Text(
            LogsScreen.compte(_entrees.length),
            style: theme.textTheme.titleSmall,
          ),
        ),
      ),
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

  Widget _blocFiltres(ThemeData theme, {required bool large}) {
    final libelle = theme.textTheme.labelLarge;
    final gravite = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(LogsScreen.gravite, style: libelle),
        const SizedBox(height: 8),
        BoutonsSegmentes<FiltreGravite>(
          values: FiltreGravite.values,
          labelOf: (g) => g.libelle,
          selected: {_filtres.gravite},
          onSelectionChanged: (s) =>
              _changer(_filtres.copyWith(gravite: s.first)),
        ),
      ],
    );
    final periode = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(LogsScreen.periode, style: libelle),
        const SizedBox(height: 8),
        BoutonsSegmentes<FiltrePeriode>(
          values: FiltrePeriode.values,
          labelOf: (p) => p.libelle,
          selected: {_filtres.periode},
          onSelectionChanged: (s) =>
              _changer(_filtres.copyWith(periode: s.first)),
        ),
      ],
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
            gravite,
            const SizedBox(height: 16),
            periode,
            const SizedBox(height: 16),
            _menuFonction(null),
            const SizedBox(height: 16),
            _champTicket(),
            const SizedBox(height: 16),
            _champTexte(),
            const SizedBox(height: 16),
            bouton,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: gravite),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: periode),
            ],
          ),
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

  /// Menu des fonctions, tiré de la liste rendue par le serveur (P49).
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
      border: const OutlineInputBorder(),
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
      border: const OutlineInputBorder(),
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
    final gravite = entree.gravite;
    final (icone, couleur) = switch (gravite) {
      GraviteJournal.erreur => (Icons.error_outline, scheme.error),
      GraviteJournal.avertissement => (
        Icons.warning_amber_outlined,
        scheme.tertiary,
      ),
      GraviteJournal.information => (Icons.info_outline, scheme.primary),
      GraviteJournal.debogage => (Icons.bug_report_outlined, scheme.outline),
      GraviteJournal.autre => (Icons.circle_outlined, scheme.onSurfaceVariant),
    };
    return ExpansionTile(
      initiallyExpanded: ouverte,
      onExpansionChanged: onOuverte,
      leading: Semantics(
        label: gravite.mot,
        child: ExcludeSemantics(child: Icon(icone, color: couleur)),
      ),
      title: Text(entree.titre, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(entree.resume),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => unawaited(_copier(context, ref)),
          icon: const Icon(Icons.copy),
          label: const Text(LogsScreen.copier),
        ),
      ],
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
          SelectableText(
            contenu,
            style: monospace
                ? theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
