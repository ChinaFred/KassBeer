import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/member.dart';

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
class InviteMemberForm extends StatefulWidget {
  const InviteMemberForm({
    super.key,
    required this.existingEmails,
    this.submitOnEnter = kIsWeb,
  });

  static const invalidEmail = 'Adresse e-mail invalide.';
  static const alreadyMember = 'Cette adresse est déjà membre.';

  /// Adresses déjà membres, en minuscules.
  final Set<String> existingEmails;

  /// Entrée valide le formulaire depuis le champ de l'adresse (web).
  final bool submitOnEnter;

  @override
  State<InviteMemberForm> createState() => _InviteMemberFormState();
}

class _InviteMemberFormState extends State<InviteMemberForm> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  MemberRole _role = MemberRole.brewer;
  String? _emailError;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) {
            if (_emailError != null) setState(() => _emailError = null);
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
          decoration: const InputDecoration(
            labelText: 'Nom (facultatif)',
            border: OutlineInputBorder(),
          ),
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
