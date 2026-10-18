import 'package:flashcards2/domain/reminders/notification_gateway.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin `flutter_local_notifications` implementation of the domain gateway.
/// Deliberately inexact (plan D2): reminders tolerate a few minutes of
/// jitter, and `inexactAllowWhileIdle` needs no special permission whose
/// revocation would silently stop recurring reminders.
class LocalNotificationGateway implements NotificationGateway {
  new({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const String channelId = 'study_reminders';
  static const String channelName = 'Study reminders';
  static const String channelDescription =
      'Daily nudges to review your flashcards.';

  bool _initialized = false;
  void Function(String payload)? _onReminderTap;

  @override
  Future<void> initialize({
    required void Function(String payload) onReminderTap,
  }) async {
    _onReminderTap = onReminderTap;
    await _ensureInitialized();

    // Cold start from a notification tap does not re-fire the initialization
    // callback; the same payload arrives via launch details instead.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) &&
        payload != null &&
        payload.isNotEmpty) {
      _onReminderTap?.call(payload);
    }
  }

  /// Scheduling paths run before the UI wires the tap handler, so the plugin
  /// is initialized lazily; a later [initialize] re-registers the handler
  /// (calling initialize twice is supported by the plugin).
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('app_icon'),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _dispatchResponse,
    );
    _initialized = true;
  }

  void _dispatchResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) _onReminderTap?.call(payload);
  }

  @override
  Future<void> cancelAll() async {
    await _ensureInitialized();
    await _plugin.cancelAll();
  }

  @override
  Future<void> schedule(ScheduledReminder reminder) async {
    await _ensureInitialized();
    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
    );
    await _plugin.zonedSchedule(
      id: reminder.id,
      title: reminder.title,
      body: reminder.body,
      scheduledDate: reminder.firstFireTime,
      notificationDetails:
          const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: reminder.weekday == null
          ? DateTimeComponents.time
          : DateTimeComponents.dayOfWeekAndTime,
      payload: reminder.payload,
    );
  }

  @override
  Future<List<int>> pendingReminderIds() async {
    await _ensureInitialized();
    final pending = await _plugin.pendingNotificationRequests();
    return [for (final request in pending) request.id];
  }

  @override
  Future<ReminderAccess> accessState() async {
    await _ensureInitialized();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // Only Android is targeted; other platforms have no runtime gate here.
    if (android == null) return ReminderAccess.granted;

    if (!(await android.areNotificationsEnabled() ?? false)) {
      return ReminderAccess.permissionDenied;
    }
    final channels = await android.getNotificationChannels() ?? const [];
    AndroidNotificationChannel? ours;
    for (final channel in channels) {
      if (channel.id == channelId) {
        ours = channel;
        break;
      }
    }
    // A never-used channel does not exist yet; nothing to mute.
    if (ours != null && ours.importance == Importance.none) {
      return ReminderAccess.channelDisabled;
    }
    return ReminderAccess.granted;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    await _ensureInitialized();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return (await android.requestNotificationsPermission()) ?? false;
  }
}
