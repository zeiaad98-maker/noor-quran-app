import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Daily wird (reading portion) reminder.
///
/// Schedules one repeating local notification at a user-chosen time
/// (default 07:00) with the Arabic text «حان وقت وردك اليومي من القرآن».
///
/// Timezone handling: `tz.initializeTimeZones()` + the device timezone
/// from flutter_timezone, falling back to Asia/Damascus (the user's
/// timezone) when the device value is unavailable. The notification
/// repeats daily via [DateTimeComponents.time].
///
/// Times are plain hour/minute ints (not TimeOfDay): this project uses
/// `material_ui`, which defines its own TimeOfDay type that differs
/// from Flutter's, so passing TimeOfDay across files would not typecheck.
///
/// All failures are swallowed: notifications must never crash the app
/// (e.g. when running in tests or on a platform without the plugin).
class ReminderService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Stable id of the daily wird notification.
  static const int wirdNotificationId = 1001;

  static const String _channelId = 'wird_daily';
  static const String _channelName = 'تذكير الورد اليومي';

  static bool _initialized = false;

  /// Default reminder time (07:00) used when nothing is saved yet.
  static const int defaultHour = 7;
  static const int defaultMinute = 0;

  /// Parses a saved "HH:MM" string into (hour, minute),
  /// falling back to the default time.
  static ({int hour, int minute}) parseTime(String? raw) {
    if (raw == null) return (hour: defaultHour, minute: defaultMinute);
    final parts = raw.split(':');
    if (parts.length != 2) return (hour: defaultHour, minute: defaultMinute);
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return (hour: defaultHour, minute: defaultMinute);
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return (hour: defaultHour, minute: defaultMinute);
    }
    return (hour: hour, minute: minute);
  }

  /// Formats an hour/minute pair as "HH:MM" for SharedPreferences.
  static String formatTime(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}'
      ':${minute.toString().padLeft(2, '0')}';

  /// Timezone + plugin setup. Safe to call more than once.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Asia/Damascus'));
      }
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        settings: const InitializationSettings(android: androidSettings),
      );
      _initialized = true;
    } catch (_) {
      // Notifications unavailable — the app works fine without them.
    }
  }

  /// Requests the runtime notification permission (Android 13+) and,
  /// when exact alarms are not yet allowed, the exact-alarm permission.
  /// Returns true when notifications can be scheduled.
  static Future<bool> requestPermissions() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return true;
      await android.requestNotificationsPermission();
      final canExact = await android.canScheduleExactNotifications();
      if (canExact == false) {
        await android.requestExactAlarmsPermission();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Schedules the daily wird reminder at [hour]:[minute]. Replaces any
  /// previous schedule. When [requestPermission] is false (startup
  /// restore) no permission dialog is shown — the permission was already
  /// granted when the user enabled the reminder.
  static Future<void> scheduleDailyWird(
    int hour,
    int minute, {
    bool requestPermission = true,
  }) async {
    try {
      await init();
      if (requestPermission) {
        await requestPermissions();
      }
      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      await _plugin.zonedSchedule(
        id: wirdNotificationId,
        scheduledDate: scheduled,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'تذكير يومي بقراءة ورد القرآن الكريم',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        title: 'تطبيق نور القرآن',
        body: 'حان وقت وردك اليومي من القرآن',
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {
      // Scheduling failed (e.g. permission denied) — keep the app
      // working; the user can re-enable the reminder from the plan
      // screen, which asks for the permission again.
      if (kDebugMode) {
        debugPrint('ReminderService: failed to schedule daily wird');
      }
    }
  }

  /// Cancels the daily wird reminder, if any.
  static Future<void> cancelWird() async {
    try {
      await _plugin.cancel(id: wirdNotificationId);
    } catch (_) {}
  }
}
