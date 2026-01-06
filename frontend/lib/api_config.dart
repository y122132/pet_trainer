class AppConfig {

  // [중요] AWS 탄력적 IP(Elastic IP) 또는 도메인을 여기에 입력하세요.
  static const String serverIp = 'localhost'; // 로컬 테스트용
  // static const String serverIp = '10.0.2.2'; // Android 에뮬레이터용
  // static const String serverIp = '54.116.28.3'; // AWS 배포용 
  static const int serverPort = 8000;

  // 1. API 기본 경로 (v1 프리픽스 포함)
  // 이제 모든 REST API는 이 baseUrl을 통해 v1 경로로 접속합니다.
  static String get baseUrl => 'http://$serverIp:$serverPort/v1';
  static String get serverBaseUrl => 'http://$serverIp:$serverPort'; // 이미지 로딩용 루트 URL

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
