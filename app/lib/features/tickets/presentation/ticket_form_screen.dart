import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/editeur_plein_ecran.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/ticket.dart';
import '../domain/ticket_screens.dart';
import 'capture_ticket.dart';
import 'ticket_statut.dart';
import 'vignette_capture.dart';

/// Paramètre de `/tickets/nouveau` qui porte le modèle de route de l'écran
/// quitté (`/recettes/:id`), jamais son adresse.
const kTicketScreenQueryParam = 'ecran';

/// Adresse du formulaire pour le modèle de route [routePattern].
String ticketFormLocation(String? routePattern) {
  if (routePattern == null || routePattern.isEmpty) return AppRoutes.newTicket;
  return Uri(
    path: AppRoutes.newTicket,
    queryParameters: {kTicketScreenQueryParam: routePattern},
  ).toString();
}

/// « Signaler ou proposer » : nouveau ticket, en plein écran.
///
/// [ecranOrigine] : modèle de route de l'écran d'où vient le membre, réduit à
/// l'ensemble fermé de `ticket_screens.dart`. [reprise] : contenu d'un ticket
/// non transmis (« Reprendre ce ticket ») ; il part comme un nouveau ticket.
///
/// Ouvert depuis le menu du compte, le formulaire prend une fois la capture de
/// l'écran quitté ([captureEnAttenteProvider]) et propose de la joindre, case
/// décochée (ADR-008, T6). Aucune capture depuis « Mes tickets », l'adresse
/// directe ou « Reprendre ».
class TicketFormScreen extends ConsumerStatefulWidget {
  const TicketFormScreen({super.key, this.ecranOrigine, this.reprise});

  final String? ecranOrigine;
  final TicketBrouillon? reprise;

  static const titre = 'Signaler ou proposer';
  static const typeMissing = 'Choisissez le type de ticket.';
  static const titleTooShort = 'Le titre doit faire au moins 5 caractères.';
  static const titleTooLong = 'Le titre doit faire au plus 100 caractères.';
  static const descriptionTooShort =
      'Décrivez le bug ou l\'idée en 10 caractères au moins.';
  static const descriptionTooLong =
      'La description doit faire au plus 2 000 caractères.';
  static const warningTitle =
      'Publié sur un site public : n\'écrivez ni nom ni adresse.';
  static const warningBody =
      'Le titre et la description seront lisibles par tous sur GitHub. Votre '
      'nom et votre adresse e-mail ne sont jamais publiés.';
  static const sentOnline = 'Ticket enregistré. Suivez-le dans Mes tickets.';
  static const sentOffline =
      'Ticket enregistré. Il partira au retour du réseau.';
  static const elementHelp = 'Menu ou fenêtre concerné.';
  static const abandonMessage = 'Le texte saisi sera perdu.';
  static const refused = 'Votre ticket a été refusé. Il n\'est pas enregistré.';
  static const captureAttach = 'Joindre une capture de l\'écran précédent';
  static const captureHelp =
      'Seul l\'administrateur la voit. Elle n\'est jamais publiée.';
  static const capturePrices =
      'La capture peut montrer vos prix : l\'administrateur la verra.';
  static const captureLabel = 'Capture de l\'écran précédent';
  static const sentWithoutCapture = 'Ticket enregistré sans la capture.';
  static const sentOfflineWithoutCapture =
      'Ticket enregistré sans la capture. Il partira au retour du réseau.';

  /// Délai d'acceptation du ticket par le serveur avant le dépôt de la
  /// capture ; au-delà, le ticket part sans elle.
  static const captureWaitTimeout = Duration(seconds: 30);

  @override
  ConsumerState<TicketFormScreen> createState() => _TicketFormScreenState();
}

class _TicketFormScreenState extends ConsumerState<TicketFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleField = GlobalKey<FormFieldState<String>>();
  final _descriptionField = GlobalKey<FormFieldState<String>>();
  final _typeKey = GlobalKey();
  final _typeFocus = FocusNode();
  final _titleFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  late final TextEditingController _title;
  late final TextEditingController _description;

  /// Créé à l'ouverture : un double appui sur « Envoyer » vise le même document.
  late final String _id;
  TicketType? _type;

  /// Écran choisi : clé de `kTicketScreenNames`, « autre » ou « inconnu ».
  late String _screen;

  /// Valeur stockée : [_screen] pour « L'écran entier », sinon un élément de
  /// `kTicketElements` de cet écran.
  late String _element;
  bool _typeError = false;
  bool _dirty = false;
  bool _sending = false;

  /// Capture de l'écran quitté, prise par le menu du compte ; `null` sans
  /// capture. En mémoire seulement.
  CaptureEcran? _capture;

  /// « Joindre une capture de l'écran précédent », décochée à l'ouverture.
  bool _joindre = false;

  @override
  void initState() {
    super.initState();
    final reprise = widget.reprise;
    // Prise une fois, et retirée du fournisseur dans tous les cas : une
    // capture ne sert qu'au formulaire ouvert juste après elle, depuis le
    // même écran.
    final capture = ref.read(captureEnAttenteProvider).prendre();
    _capture =
        reprise == null &&
            capture != null &&
            capture.ecran == ticketScreenValue(widget.ecranOrigine)
        ? capture
        : null;
    _id = ref.read(ticketsRepositoryProvider).newTicketId();
    _title = TextEditingController(text: reprise?.title ?? '');
    _description = TextEditingController(text: reprise?.description ?? '');
    _type = reprise?.type;
    final value = ticketScreenValue(reprise?.screen ?? widget.ecranOrigine);
    final screen = ticketElementScreen(value) ?? value;
    final isAdmin = ref.read(grantedAccessProvider)?.member.isAdmin ?? false;
    // Un brasseur n'a pas les écrans d'Admin dans la liste.
    _screen = !isAdmin && isAdminTicketScreen(screen)
        ? kTicketScreenUnknown
        : screen;
    // L'élément n'est jamais prérempli depuis l'écran d'origine ; « Reprendre »
    // rend celui du ticket refusé.
    _element = reprise != null && _screen == screen ? value : _screen;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _typeFocus.dispose();
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  void _changed([Object? _]) {
    if (!_dirty) setState(() => _dirty = true);
  }

  static String? _titleError(String? value) {
    final text = (value ?? '').trim();
    if (text.length < kTicketTitleMinLength) {
      return TicketFormScreen.titleTooShort;
    }
    if (text.length > kTicketTitleMaxLength) {
      return TicketFormScreen.titleTooLong;
    }
    return null;
  }

  static String? _descriptionError(String? value) {
    final text = (value ?? '').trim();
    if (text.length < kTicketDescriptionMinLength) {
      return TicketFormScreen.descriptionTooShort;
    }
    if (text.length > kTicketDescriptionMaxLength) {
      return TicketFormScreen.descriptionTooLong;
    }
    return null;
  }

  Future<void> _send() async {
    // Garde synchrone : un second appui avant la fermeture n'écrit rien.
    if (_sending) return;
    final type = _type;
    final invalid = _formKey.currentState!.validateGranularly();
    setState(() => _typeError = type == null);
    if (type == null) {
      await montrerChamp(_typeKey.currentContext);
      _typeFocus.requestFocus();
      return;
    }
    if (invalid.isNotEmpty) {
      final first = invalid.contains(_titleField.currentState)
          ? _titleField.currentState
          : invalid.first;
      await montrerChamp(first?.context);
      if (first == _titleField.currentState) {
        _titleFocus.requestFocus();
      } else if (first == _descriptionField.currentState) {
        _descriptionFocus.requestFocus();
      }
      return;
    }
    final access = ref.read(grantedAccessProvider);
    final email = access?.user.memberKey;
    if (access == null || email == null) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final id = _id;
    final brouillon = TicketBrouillon(
      type: type,
      title: _title.text.trim(),
      description: _description.text.trim(),
      screen: _element,
    );
    final repository = ref.read(ticketsRepositoryProvider);
    final errors = ref.read(errorReportServiceProvider);
    final capture = _joindre ? _capture : null;
    final written = repository.create(
      id: id,
      brouillon: brouillon,
      authorUid: access.user.uid,
      authorEmail: email,
      appVersion: _installedVersion,
      platform: kIsWeb ? 'web' : 'android',
    );
    setState(() => _dirty = false);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AppRoutes.tickets);
    }
    void voir() => unawaited(router.push(AppRoutes.ticket(id)));
    // Hors ligne, la capture ne part pas : elle n'est gardée qu'en mémoire.
    final sansCapture = capture != null && access.offline;
    annoncerAvecAction(
      messenger,
      access.offline
          ? (sansCapture
                ? TicketFormScreen.sentOfflineWithoutCapture
                : TicketFormScreen.sentOffline)
          : TicketFormScreen.sentOnline,
      action: 'Voir',
      onAction: voir,
    );
    void refuse() => annoncerAvecAction(
      messenger,
      TicketFormScreen.refused,
      action: 'Reprendre',
      onAction: () =>
          unawaited(router.push(AppRoutes.newTicket, extra: brouillon)),
    );
    // Un refus est déjà rapporté par le dépôt de données, sans le texte du
    // ticket. « Reprendre » rouvre le formulaire avec le texte envoyé.
    unawaited(written.then((_) {}, onError: (Object _) => refuse()));
    if (capture == null || sansCapture) return;
    unawaited(() async {
      // Le dépôt attend le ticket accepté par le serveur, au plus
      // [captureWaitTimeout]. `false` : ticket refusé, déjà rapporté et
      // annoncé ci-dessus ; `null` : délai dépassé.
      final accepte = await written
          .then<bool?>((_) => true, onError: (Object _) => false)
          .timeout(TicketFormScreen.captureWaitTimeout, onTimeout: () => null);
      if (accepte == false) return;
      if (accepte == null) {
        errors.reportError(
          feature: 'tickets.screenshot',
          error: TimeoutException(
            'ticket non accepté par le serveur',
            TicketFormScreen.captureWaitTimeout,
          ),
          stackTrace: StackTrace.current,
          context: 'tickets/$id step=wait',
        );
        annoncerAvecAction(
          messenger,
          TicketFormScreen.sentWithoutCapture,
          action: 'Voir',
          onAction: voir,
        );
        return;
      }
      // Dépôt de l'image, puis `attachTicketScreenshot`. Le formulaire est
      // déjà fermé ; un échec est rapporté par le dépôt de données.
      final jointe = await repository.attachScreenshot(
        ticketId: id,
        authorUid: access.user.uid,
        png: capture.png,
      );
      if (!jointe) {
        annoncerAvecAction(
          messenger,
          TicketFormScreen.sentWithoutCapture,
          action: 'Voir',
          onAction: voir,
        );
      }
    }());
  }

  /// Version installée sans `+build` ; `null` si illisible.
  String? get _installedVersion =>
      ref.read(appVersionProvider)?.split('+').first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider)?.split('+').first;
    final type = _type;
    final isAdmin = ref.watch(grantedAccessProvider)?.member.isAdmin ?? false;
    final elements = ticketElementOptions(_screen, isAdmin: isAdmin);
    const gap = SizedBox(height: 16);
    return EditeurPleinEcran(
      titre: TicketFormScreen.titre,
      closePath: AppRoutes.tickets,
      fermerParRetour: true,
      dirty: _dirty,
      saving: _sending,
      onSave: _send,
      libelleAction: 'Envoyer',
      libelleEnCours: 'Envoi',
      abandonMessage: TicketFormScreen.abandonMessage,
      body: Form(
        key: _formKey,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            // Colonne défilante et non ListView : chaque champ reste construit,
            // donc validé, même hors écran.
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Avertissement(),
                  gap,
                  Semantics(
                    header: true,
                    child: Text(
                      'Type',
                      key: _typeKey,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  RadioGroup<TicketType>(
                    groupValue: _type,
                    onChanged: (t) => setState(() {
                      _type = t;
                      _typeError = false;
                      _dirty = true;
                    }),
                    child: Column(
                      children: [
                        for (final t in TicketType.values)
                          RadioListTile<TicketType>(
                            value: t,
                            focusNode: t == TicketType.values.first
                                ? _typeFocus
                                : null,
                            contentPadding: EdgeInsets.zero,
                            title: Text(t.label),
                            subtitle: Text(t.help),
                          ),
                      ],
                    ),
                  ),
                  if (_typeError)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        TicketFormScreen.typeMissing,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  gap,
                  TextFormField(
                    key: _titleField,
                    controller: _title,
                    focusNode: _titleFocus,
                    maxLength: kTicketTitleMaxLength,
                    maxLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Titre',
                      border: OutlineInputBorder(),
                    ),
                    validator: _titleError,
                    onChanged: _changed,
                  ),
                  gap,
                  if (type != null) ...[
                    Text(
                      type.descriptionPlan,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextFormField(
                    key: _descriptionField,
                    controller: _description,
                    focusNode: _descriptionFocus,
                    maxLength: kTicketDescriptionMaxLength,
                    minLines: 5,
                    maxLines: 12,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: _descriptionError,
                    onChanged: _changed,
                  ),
                  gap,
                  DropdownButtonFormField<String>(
                    initialValue: _screen,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: const InputDecoration(
                      labelText: 'Écran concerné',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final o in ticketScreenOptions(isAdmin: isAdmin))
                        DropdownMenuItem(
                          value: o.value,
                          child: _LibelleChoix(o.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _screen = value;
                        _element = value;
                        _dirty = true;
                      });
                    },
                  ),
                  if (elements.isNotEmpty) ...[
                    gap,
                    DropdownButtonFormField<String>(
                      // Une clé par écran : changer d'écran recrée le champ sur
                      // « L'écran entier ».
                      key: ValueKey('element-$_screen'),
                      initialValue: _element,
                      isExpanded: true,
                      itemHeight: null,
                      decoration: const InputDecoration(
                        labelText: 'Élément précis',
                        helperText: TicketFormScreen.elementHelp,
                        helperMaxLines: 3,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final o in elements)
                          DropdownMenuItem(
                            value: o.value,
                            child: _LibelleChoix(o.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _element = value;
                          _dirty = true;
                        });
                      },
                    ),
                  ],
                  if (_capture case final capture?) ...[
                    gap,
                    _SectionCapture(
                      capture: capture,
                      joindre: _joindre,
                      enabled: !_sending,
                      onChanged: (value) => setState(() => _joindre = value),
                    ),
                  ],
                  gap,
                  Text(
                    envoyeAvec(
                      version: version,
                      platform: kIsWeb ? 'web' : 'android',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Section « Capture » : case « Joindre une capture de l'écran précédent »,
/// décochée à l'ouverture, et vignette de l'image ; avertissement quand
/// l'écran capturé peut montrer des prix.
class _SectionCapture extends StatelessWidget {
  const _SectionCapture({
    required this.capture,
    required this.joindre,
    required this.enabled,
    required this.onChanged,
  });

  final CaptureEcran capture;
  final bool joindre;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prix = kTicketScreensWithPrices.contains(
      ticketElementScreen(capture.ecran) ?? capture.ecran,
    );
    final aide = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(TextesCapture.titre, style: theme.textTheme.titleSmall),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: joindre,
          onChanged: enabled ? (v) => onChanged(v ?? false) : null,
          title: const Text(TicketFormScreen.captureAttach),
          subtitle: const Text(TicketFormScreen.captureHelp),
        ),
        if (prix) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.sell_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(TicketFormScreen.capturePrices, style: aide),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        VignetteCapture(
          png: capture.png,
          libelle: TicketFormScreen.captureLabel,
        ),
      ],
    );
  }
}

/// Libellé d'un choix de liste : deux lignes au plus, pour un grand texte.
class _LibelleChoix extends StatelessWidget {
  const _LibelleChoix(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label, maxLines: 2, overflow: TextOverflow.ellipsis);
}

/// Encadré toujours visible : le texte part sur un site public.
class _Avertissement extends StatelessWidget {
  const _Avertissement();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.public, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TicketFormScreen.warningTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    TicketFormScreen.warningBody,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
