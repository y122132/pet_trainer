import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pet_trainer_frontend/screens/main_title_screen.dart';
import 'package:provider/provider.dart';
import 'providers/char_provider.dart';
import 'providers/chat_provider.dart'; // [New]
import 'config/theme.dart'; // [New]

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CharProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()), // [New] Global Chat
        // 필요 시 BattleProvider 등 develop의 다른 프로바이더 추가
      ],
      child: const MyApp(),
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
        //fontFamily: 'NanumGothic', // 기본 폰트 설정 (시스템에 있으면 사용)
      ),
      locale: const Locale('ko', 'KR'), // [직접 지정] 시스템 설정 무시하고 한국어 강제 적용
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'),
        Locale('en', 'US'),
      ],
      // 앱의 첫 화면을 MainTitleScreen으로 설정
      home: const MainTitleScreen(),
    );
  }
}


