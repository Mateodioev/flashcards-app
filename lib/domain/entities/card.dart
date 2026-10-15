import 'package:flashcards2/domain/enums.dart';

/// One prompt/answer pair, the atomic unit of study.
class Card {
  const new({
    required this.id,
    required this.themeId,
    required this.front,
    required this.back,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int themeId;

  /// Markdown with inline `$LaTeX$`.
  final String front;

  final String back;
  final CardSource source;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// An image attached to a card.
///
/// Only the filesystem [path] is stored; the bytes never enter the database.
class CardImage {
  const new({
    required this.id,
    required this.cardId,
    required this.path,
    required this.position,
    this.caption,
  });

  final int id;
  final int cardId;
  final String path;
  final int position;
  final String? caption;
}
