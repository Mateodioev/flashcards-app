import 'package:drift/drift.dart';
import 'package:flashcards2/data/daos/card_dao.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/domain/entities/card.dart';
import 'package:flashcards2/domain/entities/card_search.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/entities/theme.dart';
import 'package:flashcards2/domain/repositories/card_repository.dart';
import 'package:flashcards2/domain/scheduling/due_queue.dart';

/// Drift-backed [CardRepository].
///
/// Covers the whole authoring hierarchy — themes, cards, their images and each
/// card's schedule state — mapping rows to domain entities at the boundary.
class DriftCardRepository implements CardRepository {
  new(AppDatabase db) : _dao = CardDao(db);

  final CardDao _dao;

  // --- Themes -------------------------------------------------------------

  @override
  Future<Theme?> findThemeById(int id) async {
    final row = await _dao.themeById(id);
    return row == null ? null : _themeToEntity(row);
  }

  @override
  Future<List<Theme>> findThemesByCourse(int courseId) async {
    final rows = await _dao.themesByCourse(courseId);
    return rows.map(_themeToEntity).toList();
  }

  @override
  Future<Theme> createTheme(Theme theme) async {
    final row = await _dao.createTheme(
      ThemesCompanion.insert(
        courseId: theme.courseId,
        name: theme.name,
        description: Value(theme.description),
        createdAt: Value(theme.createdAt),
      ),
    );
    return _themeToEntity(row);
  }

  @override
  Future<void> updateTheme(Theme theme) async {
    await _dao.updateTheme(_themeToRow(theme));
  }

  @override
  Future<void> deleteTheme(int id) async {
    await _dao.deleteTheme(id);
  }

  // --- Cards --------------------------------------------------------------

  @override
  Future<Card?> findCardById(int id) async {
    final row = await _dao.cardById(id);
    return row == null ? null : _cardToEntity(row);
  }

  @override
  Future<List<Card>> findCardsByTheme(int themeId) async {
    final rows = await _dao.cardsByTheme(themeId);
    return rows.map(_cardToEntity).toList();
  }

  @override
  Future<List<ScopedCard>> findCardsWithContext({
    int? courseId,
    int? themeId,
  }) async {
    final rows = await _dao.cardsInScope(courseId: courseId, themeId: themeId);
    return rows
        .map(
          (row) => ScopedCard(
            card: _cardToEntity(row.card),
            theme: _themeToEntity(row.theme),
            courseName: row.course.name,
          ),
        )
        .toList();
  }

  @override
  Future<Card> createCard(Card card) async {
    final row = await _dao.createCard(
      CardsCompanion.insert(
        themeId: card.themeId,
        front: card.front,
        back: card.back,
        source: Value(card.source),
        createdAt: Value(card.createdAt),
        updatedAt: Value(card.updatedAt),
      ),
    );
    return _cardToEntity(row);
  }

  @override
  Future<void> updateCard(Card card) async {
    await _dao.updateCard(_cardToRow(card));
  }

  @override
  Future<void> deleteCard(int id) async {
    await _dao.deleteCard(id);
  }

  // --- Images -------------------------------------------------------------

  @override
  Future<CardImage> addImage(CardImage image) async {
    final row = await _dao.addImage(
      CardImagesCompanion.insert(
        cardId: image.cardId,
        path: image.path,
        position: Value(image.position),
        caption: Value(image.caption),
      ),
    );
    return _imageToEntity(row);
  }

  @override
  Future<List<CardImage>> findImagesByCard(int cardId) async {
    final rows = await _dao.imagesByCard(cardId);
    return rows.map(_imageToEntity).toList();
  }

  @override
  Future<void> deleteImage(int id) async {
    await _dao.deleteImage(id);
  }

  // --- Schedule state -----------------------------------------------------

  @override
  Future<ScheduleState?> findScheduleState(int cardId) async {
    final row = await _dao.scheduleState(cardId);
    return row == null ? null : _scheduleToEntity(row);
  }

  @override
  Future<void> upsertScheduleState(ScheduleState state) async {
    await _dao.upsertScheduleState(
      ScheduleStatesCompanion(
        cardId: Value(state.cardId),
        stability: Value(state.stability),
        difficulty: Value(state.difficulty),
        due: Value(state.due),
        lastReview: Value(state.lastReview),
        reps: Value(state.reps),
        lapses: Value(state.lapses),
        state: Value(state.state),
        step: Value(state.step),
      ),
    );
  }

  @override
  Future<List<DueEntry>> findDueEntries({
    required DateTime dueBefore,
    int? courseId,
    int? themeId,
    int? limit,
  }) async {
    final rows = await _dao.dueCards(
      dueBefore: dueBefore,
      courseId: courseId,
      themeId: themeId,
      limit: limit,
    );
    return rows
        .map(
          (row) => DueEntry(
            cardId: row.cardId,
            themeId: row.themeId,
            courseId: row.courseId,
            due: row.due,
          ),
        )
        .toList();
  }

  @override
  Future<List<DueEntry>> findNewEntries({
    int? courseId,
    int? themeId,
    int? limit,
  }) async {
    final rows = await _dao.newCardsForCourse(
      courseId: courseId,
      themeId: themeId,
      limit: limit,
    );
    return rows
        .map(
          (row) => DueEntry(
            cardId: row.cardId,
            themeId: row.themeId,
            courseId: row.courseId,
            due: row.due,
          ),
        )
        .toList();
  }

  Theme _themeToEntity(ThemeRow row) {
    return Theme(
      id: row.id,
      courseId: row.courseId,
      name: row.name,
      description: row.description,
      createdAt: row.createdAt,
    );
  }

  ThemeRow _themeToRow(Theme theme) {
    return ThemeRow(
      id: theme.id,
      courseId: theme.courseId,
      name: theme.name,
      description: theme.description,
      createdAt: theme.createdAt,
    );
  }

  Card _cardToEntity(CardRow row) {
    return Card(
      id: row.id,
      themeId: row.themeId,
      front: row.front,
      back: row.back,
      source: row.source,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  CardRow _cardToRow(Card card) {
    return CardRow(
      id: card.id,
      themeId: card.themeId,
      front: card.front,
      back: card.back,
      source: card.source,
      createdAt: card.createdAt,
      updatedAt: card.updatedAt,
    );
  }

  CardImage _imageToEntity(CardImageRow row) {
    return CardImage(
      id: row.id,
      cardId: row.cardId,
      path: row.path,
      position: row.position,
      caption: row.caption,
    );
  }

  ScheduleState _scheduleToEntity(ScheduleStateRow row) {
    return ScheduleState(
      cardId: row.cardId,
      stability: row.stability,
      difficulty: row.difficulty,
      due: row.due,
      lastReview: row.lastReview,
      reps: row.reps,
      lapses: row.lapses,
      state: row.state,
      step: row.step,
    );
  }
}
