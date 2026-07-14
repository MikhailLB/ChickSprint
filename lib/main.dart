import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/loading_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChickSprintApp());
}

class ChickSprintApp extends StatelessWidget {
  const ChickSprintApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF2E7D32),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    return MaterialApp(
      title: 'Chick Sprint',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFC107),
          brightness: Brightness.light,
        ),
        fontFamily: 'Roboto',
      ),
      home: const LoadingScreen(),
    );
  }
}
