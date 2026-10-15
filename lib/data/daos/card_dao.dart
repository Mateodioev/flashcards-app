import 'package:drift/drift.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/tables/tables.dart';

part 'card_dao.g.dart';

/// Create/read/update/delete for the course -> theme -> card -> image
/// hierarchy, plus the card's schedule state.
@DriftAccessor(tables: [Themes, Cards, CardImages, ScheduleStates])
class CardDao extends DatabaseAccessor<AppDatabase> with _$CardDaoMixin {
  new(super.attachedDatabase);

  // --- Themes -------------------------------------------------------------

  Future<List<ThemeRow>> themesByCourse(int courseId) {
    return (select(themes)..where((t) => t.courseId.equals(courseId))).get();
  }

  Future<ThemeRow?> themeById(int id) {
    return (select(themes)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<ThemeRow> createTheme(ThemesCompanion theme) {
    return into(themes).insertReturning(theme);
  }

  Future<bool> updateTheme(ThemeRow theme) => update(themes).replace(theme);

  Future<int> deleteTheme(int id) {
    return (delete(themes)..where((t) => t.id.equals(id))).go();
  }

  // --- Cards --------------------------------------------------------------

  Future<List<CardRow>> cardsByTheme(int themeId) {
    return (select(cards)..where((t) => t.themeId.equals(themeId))).get();
  }

  Future<CardRow?> cardById(int id) {
    return (select(cards)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<CardRow> createCard(CardsCompanion card) {
    return into(cards).insertReturning(card);
  }

  Future<bool> updateCard(CardRow card) => update(cards).replace(card);

  Future<int> deleteCard(int id) {
    return (delete(cards)..where((t) => t.id.equals(id))).go();
  }

  // --- Images -------------------------------------------------------------

  Future<List<CardImageRow>> imagesByCard(int cardId) {
    return (select(cardImages)
          ..where((t) => t.cardId.equals(cardId))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
  }

  Future<CardImageRow> addImage(CardImagesCompanion image) {
    return into(cardImages).insertReturning(image);
  }

  Future<int> deleteImage(int id) {
    return (delete(cardImages)..where((t) => t.id.equals(id))).go();
  }

  // --- Schedule state -----------------------------------------------------

  Future<ScheduleStateRow?> scheduleState(int cardId) {
    return (select(
      scheduleStates,
    )..where((t) => t.cardId.equals(cardId))).getSingleOrNull();
  }

  Future<void> upsertScheduleState(ScheduleStatesCompanion state) {
    return into(scheduleStates).insertOnConflictUpdate(state);
  }
}
