import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() => runApp(const JersIrcApp());

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
        home: const HomeScreen(),
      );
}
