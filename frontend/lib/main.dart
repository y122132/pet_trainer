import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart'; // [추가] 토큰 체크용
import 'package:camera/camera.dart';
import 'providers/char_provider.dart';
import 'providers/chat_provider.dart'; // [New]
import 'screens/menu_page.dart';
import 'config/theme.dart'; // [New]
import 'package:pet_trainer_frontend/screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 저장된 토큰이 있는지 미리 확인
  final authService = AuthService();
  final String? token = await authService.getToken();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CharProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()), // [New] Global Chat
        // 필요 시 BattleProvider 등 develop의 다른 프로바이더 추가
      ],
      child: MyApp(initialToken: token),
    ),
  );
}

class MyApp extends StatelessWidget {
  final String? initialToken;
  const MyApp({super.key, this.initialToken});

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
      // 2. 토큰이 있으면 바로 게임 메인(MenuPage), 없으면 로그인 화면으로 분기
      home: initialToken != null ? MenuPage() : LoginScreen(),
    );
  }
}


