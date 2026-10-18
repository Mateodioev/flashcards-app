import 'package:drift/drift.dart' show Value;
import 'package:flashcards2/data/daos/reminder_dao.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/domain/reminders/reminder.dart';
import 'package:flashcards2/domain/reminders/reminder_repository.dart';

/// Drift-backed [ReminderRepository] — the single source of truth the
/// reconciliation loop reschedules from (plan §1).
///
/// Maps the polymorphic `targetId` onto the two FK columns (courseId /
/// themeId) that the table's CHECK constraint pairs with the scope, and the
/// nullable weekday list onto its comma-joined encoding. [upsert] enforces
/// the one-subscription-per-(scope, target) rule (plan §2) by matching the
/// existing row — for globals, the first row with no target — and replacing
/// it while preserving its id.
class DriftReminderRepository implements ReminderRepository {
  new(AppDatabase db) : _dao = ReminderDao(db);

  final ReminderDao _dao;

  @override
  Stream<List<ReminderSubscription>> watchAll() {
    return _dao.watchAll().map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<List<ReminderSubscription>> findAll() async {
    return (await _dao.findAll()).map(_toDomain).toList();
  }

  @override
  Future<ReminderSubscription> upsert(ReminderSubscription subscription) async {
    final existing = await _findRowFor(subscription);

    if (existing == null) {
      final inserted = await _dao.insertSubscription(
        ReminderSubscriptionsCompanion(
          scope: Value(subscription.scope),
          courseId: Value(_courseIdFor(subscription)),
          themeId: Value(_themeIdFor(subscription)),
          hour: Value(subscription.hour),
          minute: Value(subscription.minute),
          daysOfWeek: Value(_encodeDays(subscription.daysOfWeek)),
          enabled: Value(subscription.enabled),
        ),
      );
      return _toDomain(inserted);
    }

    final replaced = ReminderSubscriptionRow(
      id: existing.id,
      scope: subscription.scope,
      courseId: _courseIdFor(subscription),
      themeId: _themeIdFor(subscription),
      hour: subscription.hour,
      minute: subscription.minute,
      daysOfWeek: _encodeDays(subscription.daysOfWeek),
      enabled: subscription.enabled,
    );
    await _dao.updateSubscription(replaced);
    return _toDomain(replaced);
  }

  @override
  Future<void> delete(int id) async {
    await _dao.deleteSubscription(id);
  }

  Future<ReminderSubscriptionRow?> _findRowFor(
    ReminderSubscription subscription,
  ) {
    return switch (subscription.scope) {
      ReminderScope.global => _dao.findGlobal(),
      ReminderScope.course => _dao.findByCourseId(subscription.targetId!),
      ReminderScope.theme => _dao.findByThemeId(subscription.targetId!),
    };
  }

  int? _courseIdFor(ReminderSubscription subscription) {
    return subscription.scope == ReminderScope.course
        ? subscription.targetId
        : null;
  }

  int? _themeIdFor(ReminderSubscription subscription) {
    return subscription.scope == ReminderScope.theme
        ? subscription.targetId
        : null;
  }

  /// Sorted, comma-joined dayIdx (`"0,2,4"`); null or empty means daily and
  /// stores null. Sorting is defensive: the domain contract already promises
  /// ascending order, the storage encoding must hold regardless.
  String? _encodeDays(List<int>? daysOfWeek) {
    if (daysOfWeek == null || daysOfWeek.isEmpty) {
      return null;
    }
    final sorted = List<int>.of(daysOfWeek)..sort();
    return sorted.join(',');
  }

  List<int>? _decodeDays(String? daysOfWeek) {
    if (daysOfWeek == null || daysOfWeek.isEmpty) {
      return null;
    }
    return daysOfWeek.split(',').map(int.parse).toList();
  }

  ReminderSubscription _toDomain(ReminderSubscriptionRow row) {
    return ReminderSubscription(
      id: row.id,
      scope: row.scope,
      targetId: switch (row.scope) {
        ReminderScope.global => null,
        ReminderScope.course => row.courseId,
        ReminderScope.theme => row.themeId,
      },
      hour: row.hour,
      minute: row.minute,
      daysOfWeek: _decodeDays(row.daysOfWeek),
      enabled: row.enabled,
    );
  }
}
