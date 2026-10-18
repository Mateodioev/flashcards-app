// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reminder_dao.dart';

// ignore_for_file: type=lint
mixin _$ReminderDaoMixin on DatabaseAccessor<AppDatabase> {
  $CoursesTable get courses => attachedDatabase.courses;
  $ThemesTable get themes => attachedDatabase.themes;
  $ReminderSubscriptionsTable get reminderSubscriptions =>
      attachedDatabase.reminderSubscriptions;
  ReminderDaoManager get managers => ReminderDaoManager(this);
}

class ReminderDaoManager {
  final _$ReminderDaoMixin _db;
  ReminderDaoManager(this._db);
  $$CoursesTableTableManager get courses =>
      $$CoursesTableTableManager(_db.attachedDatabase, _db.courses);
  $$ThemesTableTableManager get themes =>
      $$ThemesTableTableManager(_db.attachedDatabase, _db.themes);
  $$ReminderSubscriptionsTableTableManager get reminderSubscriptions =>
      $$ReminderSubscriptionsTableTableManager(
        _db.attachedDatabase,
        _db.reminderSubscriptions,
      );
}
