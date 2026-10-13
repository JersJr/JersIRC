import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'screens/home_screen.dart';
import 'services/irc_notifications.dart';
import 'widgets/update_checker_overlay.dart';

const _brandViolet = Color(0xFF8B5CF6);
const _brandMagenta = Color(0xFFD946EF);
const _brandCyan = Color(0xFF38BDF8);
const _ink = Color(0xFF080A12);
const _surface = Color(0xFF111323);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'jersirc_connection',
      channelName: 'Parloteo',
      channelDescription: 'Mantiene activa la conexión de chat de Parloteo.',
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
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _brandViolet,
      brightness: Brightness.dark,
      primary: _brandViolet,
      secondary: _brandMagenta,
      tertiary: _brandCyan,
      surface: _surface,
    );
    return MaterialApp(
      title: 'Parloteo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _ink,
        canvasColor: _surface,
        dividerColor: Colors.white.withValues(alpha: 0.08),
        splashColor: _brandViolet.withValues(alpha: 0.12),
        highlightColor: _brandViolet.withValues(alpha: 0.06),
        appBarTheme: const AppBarTheme(
          backgroundColor: _ink,
          foregroundColor: Color(0xFFF8FAFC),
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: _surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF17192B),
          hintStyle: const TextStyle(color: Color(0xFF8589A6)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: _brandViolet, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _brandViolet,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFC4B5FD)),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF22243A),
          contentTextStyle: const TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF17192B),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
      ),
      home: const UpdateCheckerOverlay(child: HomeScreen()),
    );
  }
}
