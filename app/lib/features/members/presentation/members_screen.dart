import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/member.dart';
import 'invite_member_form.dart';
import 'members_providers.dart';

/// Admin › Membres : inviter et retirer les comptes. Réservé au rôle `admin`.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  static const loadError = 'Impossible de lire la liste des membres.';

  static String invitedMessage(String email) =>
      '$email est invité. Aucun e-mail n\'est envoyé : prévenez-le.';
  static String inviteRejected(String email) =>
      'L\'invitation de $email a échoué.';
  static String removeRejected(String email) =>
      'Le retrait de $email a échoué.';
  static String removedMessage(String email) => '$email est retiré.';
  static const emptyMessage =
      'Aucun membre. Appuyez sur Inviter pour ajouter un compte.';
  static const selfNote = 'Vous ne pouvez pas vous retirer vous-même';
  static const otherAdminNote =
      'Un administrateur se retire depuis la console Firebase.';

  Future<void> _invite(
    BuildContext context,
    WidgetRef ref,
    List<Member> members,
  ) async {
    final access = ref.read(accessStateProvider);
    if (access is! AccessGranted) return;
    final existing = {for (final m in members) m.email};
    final messenger = ScaffoldMessenger.of(context);

    final request = await showFeuilleOuDialogue<InviteRequest>(
      context: context,
      builder: (context) => InviteMemberForm(existingEmails: existing),
    );
    if (request == null) return;

    // L'écriture locale est faite à l'appel : le formulaire est déjà fermé, et la
    // ligne porte « En attente du réseau » tant que le serveur n'a pas répondu.
    final write = ref
        .read(membersRepositoryProvider)
        .invite(
          email: request.email,
          role: request.role,
          displayName: request.displayName,
          invitedByUid: access.user.uid,
        );
    messenger.showSnackBar(
      SnackBar(content: Text(invitedMessage(request.email))),
    );
    unawaited(
      write.catchError((Object _) {
        // Déjà rapportée par le dépôt de données ; le refus s'affiche, à la place
        // du message de succès s'il est encore visible.
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text(inviteRejected(request.email))),
        );
      }),
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    Member member,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text('Retirer ${member.email} ?'),
          content: const Text(
            'Ce compte n\'aura plus accès à Kass\'Beer. Ses recettes et brassins restent '
            'visibles du groupe.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Retirer'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    // Comme l'invitation : la ligne disparaît du cache dès l'appel.
    final write = ref.read(membersRepositoryProvider).remove(member.email);
    messenger.showSnackBar(
      SnackBar(content: Text(removedMessage(member.email))),
    );
    unawaited(
      write.catchError((Object _) {
        // Déjà rapportée par le dépôt de données ; le refus s'affiche, à la place
        // du message de succès s'il est encore visible.
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text(removeRejected(member.email))),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(membersListProvider);
    final access = ref.watch(accessStateProvider);
    final selfEmail = access is AccessGranted ? access.member.email : null;
    final compact = MediaQuery.sizeOf(context).width < kCompactMaxWidth;
    final members = membersAsync.value;

    final Widget body = switch (membersAsync) {
      AsyncError() when members == null => EtatErreur(
        message: loadError,
        retrying: membersAsync.isLoading,
        retryingLabel: 'Lecture en cours',
        onRetry: () => ref.invalidate(membersListProvider),
      ),
      _ when members == null => const EtatChargement(
        label: 'Chargement des membres',
      ),
      _ => ListView(
        padding: EdgeInsets.only(top: 8, bottom: compact ? 96 : 24),
        children: [
          if (membersAsync.hasError)
            BandeauListePerimee(
              retrying: membersAsync.isLoading,
              onRetry: () => ref.invalidate(membersListProvider),
            ),
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => _invite(context, ref, members),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Inviter'),
                ),
              ),
            ),
          if (members.isEmpty)
            const EtatVide(icon: Icons.group_outlined, message: emptyMessage),
          for (final member in members)
            _MemberRow(
              member: member,
              isSelf: member.email == selfEmail,
              onRemove: () => _remove(context, ref, member),
            ),
        ],
      ),
    };

    return Scaffold(
      body: body,
      floatingActionButton: compact && members != null
          ? FloatingActionButton.extended(
              onPressed: () => _invite(context, ref, members),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Inviter'),
            )
          : null,
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isSelf,
    required this.onRemove,
  });

  final Member member;
  final bool isSelf;
  final VoidCallback onRemove;

  /// Les règles refusent de retirer son propre compte et celui d'un autre admin.
  bool get _removable => !isSelf && !member.isAdmin;

  String get _roleLabel => switch (member.role) {
    MemberRole.admin => 'Administrateur',
    MemberRole.brewer => 'Brasseur',
    null => 'Rôle inconnu',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final name = member.displayName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? 'Nom non renseigné',
                  style: name == null
                      ? theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        )
                      : theme.textTheme.titleMedium,
                ),
                Text(member.email, style: muted),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Etiquette(label: _roleLabel),
                    if (isSelf) const Etiquette(label: 'Vous'),
                    if (member.hasPendingWrites)
                      const Etiquette(label: 'En attente du réseau'),
                  ],
                ),
                if (!_removable) ...[
                  const SizedBox(height: 8),
                  Text(
                    isSelf
                        ? MembersScreen.selfNote
                        : MembersScreen.otherAdminNote,
                    style: muted,
                  ),
                ],
              ],
            ),
          ),
          if (_removable)
            IconButton(
              tooltip: 'Retirer ${member.email}',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: onRemove,
              icon: const Icon(Icons.person_remove),
            ),
        ],
      ),
    );
  }
}
