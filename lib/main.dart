import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'screens/home_screen.dart';
import 'services/irc_notifications.dart';
import 'widgets/update_checker_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'jersirc_connection',
      channelName: 'JersIRC',
      channelDescription: 'Mantiene activa la conexión IRC de JersIRC.',
      channelImportance: NotificationChannelImportance.LOW,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(15000),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: false,
      allowWifiLock: false,
    ),
  );
  JersIrcNotifications.initialize();
  runApp(const JersIrcApp());
}

class JersIrcApp extends StatelessWidget {
  const JersIrcApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'JersIRC',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF91A7C4),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF11161C),
        ),
        home: const UpdateCheckerOverlay(child: HomeScreen()),
      );
}
