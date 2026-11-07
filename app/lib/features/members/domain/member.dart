import 'package:flutter/foundation.dart';

/// Rôle d'un membre, lu dans `members/{email}.role`.
enum MemberRole {
  admin('admin'),
  brewer('brewer');

  const MemberRole(this.value);

  /// Valeur stockée dans Firestore.
  final String value;

  /// Rôle de [value], ou `null` pour une valeur inconnue : elle n'ouvre aucun droit
  /// d'administration.
  static MemberRole? fromValue(Object? value) {
    for (final role in values) {
      if (role.value == value) return role;
    }
    return null;
  }
}

/// Document `members/{email}`.
@immutable
class Member {
  const Member({
    required this.email,
    required this.role,
    this.displayName,
    this.hasPendingWrites = false,
  });

  /// Identifiant du document : l'e-mail en minuscules.
  final String email;

  /// `null` quand la valeur stockée n'est ni `admin` ni `brewer`.
  final MemberRole? role;
  final String? displayName;

  /// Écriture locale pas encore reçue par le serveur (« En attente du réseau »).
  final bool hasPendingWrites;

  bool get isAdmin => role == MemberRole.admin;

  factory Member.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    bool hasPendingWrites = false,
  }) {
    final name = data['display_name'];
    return Member(
      email: id,
      role: MemberRole.fromValue(data['role']),
      displayName: name is String && name.trim().isNotEmpty
          ? name.trim()
          : null,
      hasPendingWrites: hasPendingWrites,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Member &&
      other.email == email &&
      other.role == role &&
      other.displayName == displayName &&
      other.hasPendingWrites == hasPendingWrites;

  @override
  int get hashCode => Object.hash(email, role, displayName, hasPendingWrites);
}

/// Lecture de `members/{email}` du compte connecté.
@immutable
class MemberLookup {
  const MemberLookup({required this.member, required this.fromCache});

  /// `null` : le document n'existe pas sur le serveur.
  final Member? member;

  /// Vrai quand la lecture vient du cache local : l'appareil est hors ligne.
  final bool fromCache;

  @override
  bool operator ==(Object other) =>
      other is MemberLookup &&
      other.member == member &&
      other.fromCache == fromCache;

  @override
  int get hashCode => Object.hash(member, fromCache);
}

/// Longueur maximale du nom saisi à l'invitation (`firestore.rules`).
const kMemberDisplayNameMaxLength = 80;

/// Longueur maximale d'une adresse (`firestore.rules`).
const kMemberEmailMaxLength = 254;

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Adresse saisie, en minuscules et sans espaces autour.
String normalizeMemberEmail(String input) => input.trim().toLowerCase();

/// Vrai si [normalized] (déjà passé par [normalizeMemberEmail]) est une adresse que
/// les règles acceptent comme identifiant de `members/`.
bool isValidMemberEmail(String normalized) =>
    normalized.length <= kMemberEmailMaxLength &&
    _emailPattern.hasMatch(normalized);

/// Tri de la liste des membres : administrateurs d'abord, puis par e-mail.
int compareMembers(Member a, Member b) {
  if (a.isAdmin != b.isAdmin) return a.isAdmin ? -1 : 1;
  return a.email.compareTo(b.email);
}
