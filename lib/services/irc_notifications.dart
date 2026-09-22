import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class JersIrcNotifications {
  JersIrcNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'jersirc_messages',
    'Mensajes de JersIRC',
    description: 'Menciones y mensajes privados de JersIRC.',
    importance: Importance.high,
  );

  static Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    await android?.requestNotificationsPermission();
  }

  static Future<void> show({required String title, required String body}) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'jersirc_messages',
        'Mensajes de JersIRC',
        channelDescription: 'Menciones y mensajes privados de JersIRC.',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(DateTime.now().millisecondsSinceEpoch.remainder(2147483647), title, body, details);
  }
}
