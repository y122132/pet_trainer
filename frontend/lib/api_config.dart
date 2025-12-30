import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConfig {
  static String get serverIp {
    if (kIsWeb) {
      return 'localhost'; // 웹에서는 localhost
    } else if (Platform.isAndroid) {
      return '10.0.2.2'; // 안드로이드 에뮬레이터
    } else {
      return 'localhost'; // iOS 에뮬레이터 또는 실제 기기 (네트워크 설정에 따라 다름)
    }
  }

  // [중요] AWS 탄력적 IP(Elastic IP) 또는 도메인을 여기에 입력하세요.
  // static const String serverIp = '54.116.28.3'; // AWS 배포용 
  static const int serverPort = 8000;

  // 1. API 기본 경로 (v1 프리픽스 포함)
  // 이제 모든 REST API는 이 baseUrl을 통해 v1 경로로 접속합니다.
  static String get baseUrl => 'http://$serverIp:$serverPort/v1';

  // 2. HTTP 엔드포인트 (Auth & Characters)
  static String get loginUrl => '$baseUrl/auth/login';
  static String get registerUrl => '$baseUrl/auth/register';
  static String get charactersUrl => '$baseUrl/characters';

  // 3. WebSocket URL (분석, 배틀, 채팅)
  // AI 분석 (develop 유지)
  static String get socketUrl => 'ws://$serverIp:$serverPort/ws/analysis';
  
  // 배틀 시스템 (develop 유지)
  static String get battleSocketUrl => 'ws://$serverIp:$serverPort/ws/battle';

  // 실시간 채팅 (network 신규 통합)
  // 백엔드 routers.py 설정에 따라 /v1/chat 경로를 포함합니다.
  static String chatSocketUrl(int userId) => 
      'ws://$serverIp:$serverPort/v1/chat/ws/chat/$userId';

  // 배틀 매치메이킹
  static String matchMakingSocketUrl(int userId) => 
      'ws://$serverIp:$serverPort/ws/battle/matchmaking/$userId';
}
