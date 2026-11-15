import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../tickets/presentation/tickets_providers.dart';
import '../domain/member.dart';
import 'members_providers.dart';

/// Invitation validée par le formulaire, prête à écrire.
@immutable
class InviteRequest {
  const InviteRequest({
    required this.email,
    required this.role,
    this.displayName,
  });

  /// En minuscules.
  final String email;
  final MemberRole role;

  /// `null` quand le champ est vide.
  final String? displayName;
}

/// Formulaire d'invitation. Rend un [InviteRequest] par `Navigator.pop`, ou rien sur
/// « Annuler ».
class InviteMemberForm extends ConsumerStatefulWidget {
  const InviteMemberForm({
    super.key,
    required this.existingEmails,
    this.submitOnEnter = kIsWeb,
  });

  static const invalidEmail = 'Adresse e-mail invalide.';
  static const alreadyMember = 'Cette adresse est déjà membre.';
  static const consoleHint =
      'Google refuse la connexion tant que l\'adresse n\'est pas dans les '
      'utilisateurs test du projet. Ajoutez-la dans la console Google.';
  static const consoleButton = 'Copier l\'adresse et ouvrir la console Google';
  static String consoleCopied(String email) =>
      'Adresse copiée ($email) : collez-la dans « Utilisateurs test » › '
      '« Ajouter des utilisateurs ».';
  static const consoleNoEmail =
      'Aucune adresse valide à copier : saisissez-la d\'abord.';
  static const consoleCopyFailed =
      'Copie impossible : recopiez l\'adresse à la main.';
  static const consoleOpenFailure =
      'Impossible d\'ouvrir la console. Adresse de la page :';

  /// Adresses déjà membres, en minuscules.
  final Set<String> existingEmails;

  /// Entrée valide le formulaire depuis le champ de l'adresse (web).
  final bool submitOnEnter;

  @override
  ConsumerState<InviteMemberForm> createState() => _InviteMemberFormState();
}

class _InviteMemberFormState extends ConsumerState<InviteMemberForm> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  MemberRole _role = MemberRole.brewer;
  String? _emailError;
  bool _consoleBusy = false;
  String? _consoleMessage;
  bool _consoleMessageIsError = false;
  Uri? _consoleFailedUri;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final email = normalizeMemberEmail(_email.text);
    String? error;
    if (!isValidMemberEmail(email)) {
      error = InviteMemberForm.invalidEmail;
    } else if (widget.existingEmails.contains(email)) {
      error = InviteMemberForm.alreadyMember;
    }
    if (error != null) {
      setState(() => _emailError = error);
      return;
    }
    final name = _name.text.trim();
    Navigator.of(context).pop(
      InviteRequest(
        email: email,
        role: _role,
        displayName: name.isEmpty ? null : name,
      ),
    );
  }

  /// Copie l'adresse saisie si elle est valide, puis ouvre la page des
  /// utilisateurs test dans le navigateur.
  Future<void> _openConsole(Uri uri) async {
    final errors = ref.read(errorReportServiceProvider);
    final open = ref.read(ouvrirLienProvider);
    setState(() {
      _consoleBusy = true;
      _consoleMessage = null;
      _consoleFailedUri = null;
    });
    final email = normalizeMemberEmail(_email.text);
    var copied = false;
    final valid = isValidMemberEmail(email);
    if (valid) {
      try {
        await Clipboard.setData(ClipboardData(text: email));
        copied = true;
      } catch (error, stackTrace) {
        errors.reportError(
          feature: 'members.copy_email',
          error: error,
          stackTrace: stackTrace,
          context: 'copie de l\'adresse invitée',
        );
      }
    }
    Object? error;
    StackTrace? stackTrace;
    var opened = false;
    try {
      opened = await open(uri);
    } catch (e, st) {
      error = e;
      stackTrace = st;
    }
    if (!opened) {
      errors.reportError(
        feature: 'members.open_console',
        error: error ?? StateError('ouverture refusée par le système'),
        stackTrace: stackTrace ?? StackTrace.current,
        context: 'page des utilisateurs test de la console Google',
      );
    }
    if (!mounted) return;
    setState(() {
      _consoleBusy = false;
      _consoleMessage = copied
          ? InviteMemberForm.consoleCopied(email)
          : valid
          ? InviteMemberForm.consoleCopyFailed
          : InviteMemberForm.consoleNoEmail;
      _consoleMessageIsError = valid && !copied;
      _consoleFailedUri = opened ? null : uri;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final consoleUri = consoleUtilisateursTest(
      ref.watch(firebaseProjectIdProvider),
    );
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Inviter un membre', style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          textInputAction: widget.submitOnEnter
              ? TextInputAction.done
              : TextInputAction.next,
          inputFormatters: [_LowerCaseFormatter()],
          decoration: InputDecoration(
            labelText: 'Adresse e-mail Google',
            errorText: _emailError,
          ),
          onChanged: (_) {
            if (_emailError != null || _consoleMessage != null) {
              setState(() {
                _emailError = null;
                _consoleMessage = null;
              });
            }
          },
          onSubmitted: (_) =>
              widget.submitOnEnter ? _submit() : _nameFocus.requestFocus(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          focusNode: _nameFocus,
          maxLength: kMemberDisplayNameMaxLength,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Nom (facultatif)'),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        Text('Rôle', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<MemberRole>(
          segments: const [
            ButtonSegment(value: MemberRole.brewer, label: Text('Brasseur')),
            ButtonSegment(
              value: MemberRole.admin,
              label: Text('Administrateur'),
            ),
          ],
          selected: {_role},
          onSelectionChanged: (selection) =>
              setState(() => _role = selection.single),
        ),
        if (consoleUri != null) ...[
          const SizedBox(height: 16),
          Text(InviteMemberForm.consoleHint, style: muted),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _consoleBusy ? null : () => _openConsole(consoleUri),
              icon: const Icon(Icons.open_in_new),
              label: const Text(InviteMemberForm.consoleButton),
            ),
          ),
          if (_consoleMessage case final message?)
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: _consoleMessageIsError
                    ? theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      )
                    : muted,
              ),
            ),
          if (_consoleFailedUri case final failed?) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                InviteMemberForm.consoleOpenFailure,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            SelectableText(failed.toString()),
          ],
        ],
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(onPressed: _submit, child: const Text('Inviter')),
          ],
        ),
      ],
    );
  }
}

/// Met l'adresse en minuscules pendant la saisie.
class _LowerCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final lower = newValue.text.toLowerCase();
    if (lower.length == newValue.text.length) {
      return newValue.copyWith(text: lower);
    }
    // Une minuscule plus longue que sa majuscule (« İ ») décale la sélection.
    return TextEditingValue(
      text: lower,
      selection: TextSelection.collapsed(offset: lower.length),
    );
  }
}
