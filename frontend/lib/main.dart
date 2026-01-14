// frontend/lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config/theme.dart';
import 'providers/char_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/main_title_screen.dart';
import 'config/global_settings.dart';
import 'services/edge_game_logic.dart'; // [NEW] Config Sync

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GlobalSettings.load();
  await EdgeGameConfig.loadFromBackend(); // [NEW] Sync Server Config

  
  runApp(
    OverlaySupport(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CharProvider()),
          ChangeNotifierProvider(create: (_) => ChatProvider()),
        ],
        child: const MyApp(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PetTrainer',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      // [Locale 설정]
      locale: const Locale('ko', 'KR'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'),
        Locale('en', 'US'),
      ],
      
      // [Entry Point] 항상 타이틀 스크린부터 시작
      home: const MainTitleScreen(),
    );
  }
}
