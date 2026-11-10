import 'package:kass_beer/features/tickets/domain/ticket.dart';

/// Ticket de test ; [createdAt] vaut le 8 novembre 2026 sauf `null` explicite.
Ticket unTicket({
  String id = 't1',
  TicketType type = TicketType.bug,
  String title = 'Densité fausse',
  String description = 'La densité affichée est fausse.',
  String screen = '/recettes/:id',
  TicketStatus status = TicketStatus.received,
  String? appVersion = '0.1.0',
  String? platform = 'android',
  Object? createdAt = _defaultDate,
  DateTime? statusChangedAt,
  DateTime? seenByAuthorAt,
  String? replyText,
  String? deliveredPrUrl,
  String? deliveredVersion,
  bool hasPendingWrites = false,
}) => Ticket(
  id: id,
  type: type,
  title: title,
  description: description,
  screen: screen,
  status: status,
  appVersion: appVersion,
  platform: platform,
  createdAt: identical(createdAt, _defaultDate)
      ? DateTime(2026, 11, 8, 9, 30)
      : createdAt as DateTime?,
  statusChangedAt: statusChangedAt,
  seenByAuthorAt: seenByAuthorAt,
  replyText: replyText,
  deliveredPrUrl: deliveredPrUrl,
  deliveredVersion: deliveredVersion,
  hasPendingWrites: hasPendingWrites,
);

const Object _defaultDate = Object();
