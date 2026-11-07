import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
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

  Future<void> _invite(
    BuildContext context,
    WidgetRef ref,
    List<Member> members,
  ) async {
    final access = ref.read(accessStateProvider);
    if (access is! AccessGranted) return;
    final existing = {for (final m in members) m.email};
    final compact = MediaQuery.sizeOf(context).width < kCompactMaxWidth;
    final messenger = ScaffoldMessenger.of(context);

    final request = compact
        ? await showModalBottomSheet<InviteRequest>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (context) => Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                0,
                24,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: InviteMemberForm(existingEmails: existing),
              ),
            ),
          )
        : await showDialog<InviteRequest>(
            context: context,
            builder: (context) => Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kDialogMaxWidth),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: InviteMemberForm(existingEmails: existing),
                ),
              ),
            ),
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
        // Déjà rapportée par le dépôt de données ; le refus s'affiche.
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
    final write = ref.read(membersRepositoryProvider).remove(member.email);
    unawaited(
      write.catchError((Object _) {
        // Déjà rapportée par le dépôt de données ; le refus s'affiche.
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
        onRetry: () => ref.invalidate(membersListProvider),
      ),
      _ when members == null => const EtatChargement(
        label: 'Chargement des membres',
      ),
      _ => ListView(
        padding: EdgeInsets.only(top: 8, bottom: compact ? 96 : 24),
        children: [
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
            const EtatVide(
              icon: Icons.group_outlined,
              message: 'Aucun membre.',
            ),
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
                    _Tag(label: _roleLabel),
                    if (isSelf) const _Tag(label: 'Vous'),
                    if (member.hasPendingWrites)
                      const _Tag(label: 'En attente du réseau'),
                  ],
                ),
                if (isSelf) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Vous ne pouvez pas vous retirer vous-même',
                    style: muted,
                  ),
                ],
              ],
            ),
          ),
          if (!isSelf)
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

/// Étiquette non interactive.
class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: scheme.onSecondaryContainer),
        ),
      ),
    );
  }
}
