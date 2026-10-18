import 'package:meta/meta.dart';

/// What a reminder subscription fires for (docs/reminder_notifications_plan.md
/// §2): everything, one specific course, or one specific theme.
enum ReminderScope { global, course, theme }

/// The user's single persisted preference for one target. Plan §2:
/// `{ scope, targetId?, hour, minute, daysOfWeek?, enabled }`, with exactly one
/// subscription per (scope, target) — the repository upserts on that key.
@immutable
class ReminderSubscription {
  const new({
    required this.scope,
    required this.hour,
    required this.minute,
    this.id = 0,
    this.targetId,
    this.daysOfWeek,
    this.enabled = true,
  });

  /// Drift row id; `0` means "not persisted yet".
  final int id;

  final ReminderScope scope;

  /// Course id or theme id depending on [scope]; `null` for
  /// [ReminderScope.global].
  final int? targetId;

  /// Local time of day, 0–23 and 0–59.
  final int hour;
  final int minute;

  /// Selected weekdays as dayIdx (0 = Monday … 6 = Sunday, plan §4), sorted
  /// ascending. A `null` or empty list means "every day" (plan D3: v1).
  final List<int>? daysOfWeek;

  /// A denied OS permission keeps the row but stores it disabled (plan §T5),
  /// so re-granting only flips this flag instead of losing the subscription.
  final bool enabled;

  bool get isDaily => daysOfWeek == null || daysOfWeek!.isEmpty;

  ReminderSubscription copyWith({
    int? id,
    ReminderScope? scope,
    int? hour,
    int? minute,
    List<int>? daysOfWeek,
    bool? enabled,
  }) {
    return ReminderSubscription(
      id: id ?? this.id,
      scope: scope ?? this.scope,
      targetId: targetId,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderSubscription &&
      other.id == id &&
      other.scope == scope &&
      other.targetId == targetId &&
      other.hour == hour &&
      other.minute == minute &&
      _listEquals(other.daysOfWeek, daysOfWeek) &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(
        id,
        scope,
        targetId,
        hour,
        minute,
        daysOfWeek == null ? null : Object.hashAll(daysOfWeek!),
        enabled,
      );

  @override
  String toString() => 'ReminderSubscription(id: $id, scope: $scope, '
      'targetId: $targetId, $hour:$minute, days: $daysOfWeek, '
      'enabled: $enabled)';

  static bool _listEquals(List<int>? a, List<int>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
