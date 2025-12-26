class AppConfig {
  // [중요] AWS 탄력적 IP(Elastic IP) 또는 도메인을 여기에 입력하세요.
  /*  로컬 테스트 시: '192.168.0.x' 또는 'localhost'  */
  // static const String serverIp = 'localhost';
  /*  Android Studio 테스트 시: '10.0.2.2'  */
  static const String serverIp = '10.0.2.2';
  /*  AWS 배포 시: '3.12.xxx.xxx' (할당받은 공인 IP)  */
  // static const String serverIp = '54.116.28.3'; 
 
  static const int serverPort = 8000;

  // HTTP 기본 URL
  static String get baseUrl => 'http://$serverIp:$serverPort';

  // WebSocket URL
  static String get socketUrl => 'ws://$serverIp:$serverPort/ws/analysis';
}
