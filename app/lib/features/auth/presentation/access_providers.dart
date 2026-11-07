import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../members/domain/member.dart';
import '../domain/session_user.dart';

/// Pas de nouvelle tentative automatique : une panne s'affiche, et « Réessayer »
/// relance la lecture.
Duration? _noRetry(int retryCount, Object error) => null;

/// Compte connecté ; `null` sans session.
final sessionUserProvider = StreamProvider<SessionUser?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
  retry: _noRetry,
);

/// Document `members/{email}` du compte [emailKey].
final memberLookupProvider = StreamProvider.family<MemberLookup, String>(
  (ref, emailKey) => ref.watch(membersRepositoryProvider).watchMember(emailKey),
  retry: _noRetry,
);

/// Où en est l'accès du compte à l'application.
@immutable
sealed class AccessState {
  const AccessState();
}

/// Session ou document `members/` pas encore lus.
class AccessLoading extends AccessState {
  const AccessLoading();
}

class AccessSignedOut extends AccessState {
  const AccessSignedOut();
}

/// Connecté, mais `members/{email}` n'existe pas sur le serveur.
class AccessNotInvited extends AccessState {
  const AccessNotInvited(this.user);

  final SessionUser user;
}

/// Lecture de la session ou du document impossible : jamais « non invité ».
class AccessFailed extends AccessState {
  const AccessFailed(this.error);

  final Object error;
}

class AccessGranted extends AccessState {
  const AccessGranted({required this.user, required this.member, required this.offline});

  final SessionUser user;
  final Member member;

  /// Le document du membre vient du cache : l'appareil est hors ligne.
  final bool offline;
}

/// État d'accès, déduit de la session et de `members/{email}`.
final accessStateProvider = Provider<AccessState>((ref) {
  final session = ref.watch(sessionUserProvider);
  switch (session) {
    case AsyncError(:final error):
      return AccessFailed(error);
    case AsyncData(:final value):
      final user = value;
      if (user == null) return const AccessSignedOut();
      final key = user.memberKey;
      if (key == null || key.isEmpty) {
        // Un compte sans adresse n'a pas de document members/ : il n'ouvre rien.
        return AccessNotInvited(user);
      }
      final lookup = ref.watch(memberLookupProvider(key));
      switch (lookup) {
        case AsyncError(:final error):
          return AccessFailed(error);
        case AsyncData(:final value):
          final member = value.member;
          if (member == null) return AccessNotInvited(user);
          return AccessGranted(user: user, member: member, offline: value.fromCache);
        default:
          return const AccessLoading();
      }
    default:
      return const AccessLoading();
  }
});

/// Relance la lecture de l'accès (« Réessayer », « Vérifier à nouveau »).
void retryAccess(WidgetRef ref) {
  final user = ref.read(sessionUserProvider).value;
  final key = user?.memberKey;
  if (key != null && key.isNotEmpty) ref.invalidate(memberLookupProvider(key));
  if (ref.read(sessionUserProvider).hasError) ref.invalidate(sessionUserProvider);
}

/// Vrai pendant une nouvelle lecture de la session ou du membre.
final accessRefreshingProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionUserProvider);
  if (session.isLoading) return true;
  final key = session.value?.memberKey;
  if (key == null || key.isEmpty) return false;
  return ref.watch(memberLookupProvider(key)).isLoading;
});
