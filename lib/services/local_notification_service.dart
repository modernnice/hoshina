import 'package:drama_tracker/services/watchlist_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();
  static const int defaultReminderHour = 20;
  static const int defaultReminderMinute = 0;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final String _channelId = 'anime_update_channel';
  final String _channelName = '番剧更新提醒';
  final String _channelDescription = '每周更新提醒';

  bool _initialized = false;
  int? _pendingSubjectId;
  void Function(int subjectId)? _tapHandler;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    tz.initializeTimeZones();
    final timezoneName = await FlutterTimezone.getLocalTimezone();
    try {
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );
    const macos = DarwinInitializationSettings(
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: macos,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        _handlePayload(response.payload);
      },
      onDidReceiveBackgroundNotificationResponse: _onDidReceiveBackgroundNotificationResponse,
    );

    await _requestPermissions();
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _handlePayload(launchDetails?.notificationResponse?.payload);
    }
    _initialized = true;
  }

  Future<void> _requestPermissions() async {
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  void setTapHandler(void Function(int subjectId) handler) {
    _tapHandler = handler;
  }

  int? consumePendingSubjectId() {
    final pending = _pendingSubjectId;
    _pendingSubjectId = null;
    return pending;
  }

  Future<void> scheduleWeeklyReminder({
    required int subjectId,
    required String animeName,
    required int airWeekday,
    int hour = defaultReminderHour,
    int minute = defaultReminderMinute,
  }) async {
    if (airWeekday < 1 || airWeekday > 7) {
      return;
    }
    final safeAnimeName = animeName.trim().isEmpty ? '番剧' : animeName.trim();
    final scheduledDate = _nextWeeklyDateTime(airWeekday, hour, minute);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.zonedSchedule(
      subjectId,
      '《$safeAnimeName》更新啦',
      '快去追更～',
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: subjectId.toString(),
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  static String formatReminderTimeText(int hour, int minute) {
    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> cancelReminder(int subjectId) async {
    await _plugin.cancel(subjectId);
  }

  Future<void> syncAllFromStorage(WatchlistStorage storage) async {
    final items = storage.getAllProgresses();
    for (final progress in items) {
      try {
        if (progress.reminderEnabled &&
            progress.updateWeekday >= 1 &&
            progress.updateWeekday <= 7) {
          await scheduleWeeklyReminder(
            subjectId: progress.subjectId,
            animeName: progress.name,
            airWeekday: progress.updateWeekday,
            hour: progress.reminderHour,
            minute: progress.reminderMinute,
          );
        } else {
          await cancelReminder(progress.subjectId);
        }
      } catch (e) {
        // Do not let a single malformed reminder crash the whole startup flow.
        debugPrint('Failed to sync reminder for subject ${progress.subjectId}: $e');
      }
    }
  }

  tz.TZDateTime _nextWeeklyDateTime(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    while (scheduled.weekday != weekday || scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  void _handlePayload(String? payload) {
    final subjectId = int.tryParse(payload ?? '');
    if (subjectId == null) {
      return;
    }
    final handler = _tapHandler;
    if (handler != null) {
      handler(subjectId);
      return;
    }
    _pendingSubjectId = subjectId;
  }
}

@pragma('vm:entry-point')
void _onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  LocalNotificationService.instance;
}
