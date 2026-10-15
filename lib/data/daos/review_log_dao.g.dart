// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_log_dao.dart';

// ignore_for_file: type=lint
mixin _$ReviewLogDaoMixin on DatabaseAccessor<AppDatabase> {
  $CoursesTable get courses => attachedDatabase.courses;
  $ThemesTable get themes => attachedDatabase.themes;
  $CardsTable get cards => attachedDatabase.cards;
  $ReviewLogsTable get reviewLogs => attachedDatabase.reviewLogs;
  ReviewLogDaoManager get managers => ReviewLogDaoManager(this);
}

class ReviewLogDaoManager {
  final _$ReviewLogDaoMixin _db;
  ReviewLogDaoManager(this._db);
  $$CoursesTableTableManager get courses =>
      $$CoursesTableTableManager(_db.attachedDatabase, _db.courses);
  $$ThemesTableTableManager get themes =>
      $$ThemesTableTableManager(_db.attachedDatabase, _db.themes);
  $$CardsTableTableManager get cards =>
      $$CardsTableTableManager(_db.attachedDatabase, _db.cards);
  $$ReviewLogsTableTableManager get reviewLogs =>
      $$ReviewLogsTableTableManager(_db.attachedDatabase, _db.reviewLogs);
}
