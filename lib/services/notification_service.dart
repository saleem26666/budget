import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../database_helper.dart';
import '../utils/platform_utils.dart';
import '../widgets/family_expiry_panel.dart';
import 'budget_alert_service.dart';
import 'recurring_service.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _enabledKey = 'bp_notifications_enabled';
  static const _hourKey = 'bp_notify_hour';
  static const _askedKey = 'bp_notify_permission_asked';
  static const _channelId = 'budget_pro_reminders';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _tzReady = false;

  bool get isSupported => isMobilePlatform;

  Future<bool> get enabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (!value) {
      await cancelAll();
    } else {
      await rescheduleActiveProfile();
    }
  }

  Future<int> get notifyHour async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_hourKey) ?? 9).clamp(6, 21);
  }

  Future<void> setNotifyHour(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey, hour.clamp(6, 21));
    await rescheduleActiveProfile();
  }

  Future<void> init() async {
    if (!isSupported || _ready) return;
    try {
      await _ensureTimeZone();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin),
      );
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          'Reminders',
          description: 'Recurring, documents, birthdays, budgets',
          importance: Importance.high,
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('NotificationService.init: $e');
    }
  }

  Future<bool> requestPermission({bool forceAsk = false}) async {
    if (!isSupported) return false;
    await init();
    final prefs = await SharedPreferences.getInstance();
    if (!forceAsk && (prefs.getBool(_askedKey) ?? false)) {
      if (Platform.isAndroid) return Permission.notification.isGranted;
    }
    await prefs.setBool(_askedKey, true);
    try {
      if (Platform.isAndroid) {
        return (await Permission.notification.request()).isGranted;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  Future<void> rescheduleActiveProfile({
    List<BudgetAlert> budgetAlerts = const [],
  }) async {
    if (!isSupported) return;
    await init();
    if (!_ready) return;
    if (!await enabled) {
      await cancelAll();
      return;
    }
    if (Platform.isAndroid && !await Permission.notification.isGranted) return;

    await cancelAll();
    final hour = await notifyHour;
    var id = 8000;

    try {
      final recurrences =
          await DatabaseHelper.instance.getRecurringTransactions();
      for (final row in recurrences) {
        if ((row['enabled'] ?? 1) == 0 || (row['notify'] ?? 1) == 0) continue;
        final due = DateTime.tryParse(row['next_due']?.toString() ?? '');
        if (due == null) continue;
        final when = DateTime(due.year, due.month, due.day, hour);
        if (when.isBefore(DateTime.now())) continue;
        await _schedule(
          id++,
          'Due today: ${row['title'] ?? 'Recurring'}',
          '${RecurringService.labelFor((row['frequency'] ?? 'monthly').toString())} payment is due',
          when,
        );
      }
    } catch (e) {
      debugPrint('schedule recurring: $e');
    }

    try {
      final items = await FamilyExpiryCenter.load(withinDays: 30);
      for (final item in items) {
        final when = DateTime(
            item.expiry.year, item.expiry.month, item.expiry.day, hour);
        if (when.isBefore(DateTime.now())) {
          if (item.status == 'expired' || item.status == 'today') {
            await _showNow(
              id++,
              item.status == 'today'
                  ? '${item.memberName} — ${item.docType}'
                  : 'Expired: ${item.memberName}',
              item.docType,
            );
          }
          continue;
        }
        await _schedule(
          id++,
          '${item.memberName} · ${item.docType}',
          item.status == 'expired' ? 'Already expired' : 'Coming up soon',
          when,
        );
      }
    } catch (e) {
      debugPrint('schedule vault: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final todayKey = DateTime.now().toIso8601String().substring(0, 10);
      for (final alert in budgetAlerts) {
        final key = 'bp_budget_notified_${alert.title}_$todayKey';
        if (prefs.getBool(key) ?? false) continue;
        await _showNow(
          id++,
          alert.isOverBudget ? 'Over budget' : 'Budget warning',
          '${alert.title}: ${alert.message}',
        );
        await prefs.setBool(key, true);
      }
    } catch (_) {}
  }

  Future<void> _ensureTimeZone() async {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Karachi'));
      } catch (_) {}
    }
    _tzReady = true;
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Reminders',
          channelDescription: 'Recurring, documents, birthdays, budgets',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  Future<void> _schedule(
      int id, String title, String body, DateTime when) async {
    if (when.isBefore(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime(tz.local, when.year, when.month, when.day, when.hour,
            when.minute),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('zonedSchedule: $e');
    }
  }

  Future<void> _showNow(int id, String title, String body) async {
    try {
      await _plugin.show(id, title, body, _details);
    } catch (_) {}
  }
}
