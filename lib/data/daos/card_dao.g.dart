// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'card_dao.dart';

// ignore_for_file: type=lint
mixin _$CardDaoMixin on DatabaseAccessor<AppDatabase> {
  $CoursesTable get courses => attachedDatabase.courses;
  $ThemesTable get themes => attachedDatabase.themes;
  $CardsTable get cards => attachedDatabase.cards;
  $CardImagesTable get cardImages => attachedDatabase.cardImages;
  $ScheduleStatesTable get scheduleStates => attachedDatabase.scheduleStates;
  CardDaoManager get managers => CardDaoManager(this);
}

class CardDaoManager {
  final _$CardDaoMixin _db;
  CardDaoManager(this._db);
  $$CoursesTableTableManager get courses =>
      $$CoursesTableTableManager(_db.attachedDatabase, _db.courses);
  $$ThemesTableTableManager get themes =>
      $$ThemesTableTableManager(_db.attachedDatabase, _db.themes);
  $$CardsTableTableManager get cards =>
      $$CardsTableTableManager(_db.attachedDatabase, _db.cards);
  $$CardImagesTableTableManager get cardImages =>
      $$CardImagesTableTableManager(_db.attachedDatabase, _db.cardImages);
  $$ScheduleStatesTableTableManager get scheduleStates =>
      $$ScheduleStatesTableTableManager(
        _db.attachedDatabase,
        _db.scheduleStates,
      );
}
