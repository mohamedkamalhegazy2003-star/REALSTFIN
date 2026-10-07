import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import 'db.dart';
import 'utils.dart';

const String _taskUnique = 'rent_alerts_v1';
const String _taskName = 'rentAlerts';

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

/// نقطة دخول المهمة الدورية (تعمل في الخلفية كل 4 ساعات)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await runAlertCheck();
    } catch (_) {}
    return true;
  });
}

Future<void> runAlertCheck() async {
  if ((await DB.getSetting('notifications_enabled')) != '1') return;
  soonDays = int.tryParse(await DB.getSetting('soon_days') ?? '') ?? 3;
  final items = await DB.all();
  final alerts = computeAlerts(items);
  if (alerts.isEmpty) return;

  final late = <String>[];
  final soon = <String>[];
  for (final i in alerts) {
    final d = daysUntilDue(i);
    final label = '${i['tenant_name'] ?? ''} (${i['name'] ?? ''})';
    if (d == null || d < 0) {
      late.add(label);
    } else {
      soon.add(label);
    }
  }
  String join(List<String> l) =>
      l.take(3).join('، ') + (l.length > 3 ? ' و${l.length - 3} آخرين' : '');
  final parts = <String>[];
  if (late.isNotEmpty) parts.add('متأخر: ${join(late)}');
  if (soon.isNotEmpty) parts.add('قريب الاستحقاق: ${join(soon)}');
  await Notifier.show('تنبيه الإيجارات', parts.join('\n'));
}

class Notifier {
  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    _inited = true;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// صلاحية POST_NOTIFICATIONS (أندرويد 13+)
  static Future<bool> requestPermission() async {
    await init();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  static Future<bool> permissionGranted() async {
    await init();
    return await _android?.areNotificationsEnabled() ?? false;
  }

  static Future<void> show(String title, String body) async {
    await init();
    await _plugin.show(
      1001,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'rent_alerts',
          'تنبيهات الإيجارات',
          channelDescription: 'تنبيهات الإيجارات المتأخرة وقريبة الاستحقاق',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  }

  /// إشعار تسجيل الدخول
  static Future<void> showLogin(String name) async {
    try {
      await init();
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final time = '${now.year}/${two(now.month)}/${two(now.day)} - ${two(now.hour)}:${two(now.minute)}';
      final body = 'تم تسجيل دخول $name بنجاح\n$time';
      await _plugin.show(
        1002,
        'تم تسجيل الدخول',
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'login_alerts',
            'إشعارات تسجيل الدخول',
            channelDescription: 'إشعار عند تسجيل الدخول إلى التطبيق',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
      );
    } catch (_) {}
  }

  /// جدولة مهمة كل 4 ساعات
  static Future<void> schedule() async {
    try {
      await Workmanager().registerPeriodicTask(
        _taskUnique,
        _taskName,
        frequency: const Duration(hours: 4),
      );
    } catch (_) {}
  }

  static Future<void> cancel() async {
    try {
      await Workmanager().cancelByUniqueName(_taskUnique);
    } catch (_) {}
  }

  /// يُستدعى بعد تسجيل الدخول: أول مرة يطلب الصلاحية ويفعّل الإشعارات
  static Future<void> bootstrap() async {
    try {
      await init();
      var enabled = await DB.getSetting('notifications_enabled');
      if (enabled == null) {
        final ok = await requestPermission();
        enabled = ok ? '1' : '0';
        await DB.setSetting('notifications_enabled', enabled);
      }
      if (enabled == '1') {
        await schedule();
      }
    } catch (_) {}
  }
}
