import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart'; // [추가] 토큰 체크용
import 'package:camera/camera.dart';
import 'providers/char_provider.dart';
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
      ),
      // 2. 토큰이 있으면 바로 게임 메인(MenuPage), 없으면 로그인 화면으로 분기
      home: initialToken != null ? MenuPage() : LoginScreen(),
    );
  }
}


