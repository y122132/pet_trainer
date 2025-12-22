import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:pet_trainer_frontend/config.dart';

class SocketClient {
  WebSocketChannel? _channel;
  // 소켓 데이터를 UI로 중계하기 위한 Broadcast 스트림 컨트롤러
  final StreamController<dynamic> _streamController = StreamController<dynamic>.broadcast();
  
  // 현재 연결 상태
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  // 외부(UI)에서 구독할 스트림
  Stream<dynamic> get stream => _streamController.stream;

  // 백엔드 주소 (Config에서 가져옴)
  final String _wsUrl = AppConfig.socketUrl; // ws://IP:PORT/ws/analysis

  /// 웹소켓 서버에 연결합니다.
  /// [petType]: 반려동물 종류 (예: 'dog', 'cat')
  /// [difficulty]: 난이도 ('easy', 'hard')
  /// [mode]: 훈련 모드 ('playing', 'feeding', 'interaction')
  Future<void> connect(String petType, String difficulty, String mode) async {
    if (_isConnected) return; // 이미 연결되어 있으면 무시

    try {
      // URL 쿼리 파라미터 구성 (사용자 ID는 1로 고정 - 추후 인증 연동 필요)
      final uri = Uri.parse('$_wsUrl/1?pet_type=$petType&difficulty=$difficulty&mode=$mode');
      print("Socket Connecting to: $uri");
      
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;

      // 채널로부터 메시지를 받아 컨트롤러로 전달 (UI에서 listen 가능하도록)
      _channel!.stream.listen(
        (message) {
          _streamController.add(message);
        },
        onDone: () {
          print("Socket Disconnected (서버 종료)");
          _isConnected = false;
        },
        onError: (error) {
          print("Socket Error (오류 발생): $error");
          _isConnected = false;
        },
      );
    } catch (e) {
      print("Socket Connection Failed (연결 실패): $e");
      _isConnected = false;
    }
  }

  /// 메시지(Base64 이미지 문자열)를 서버로 전송합니다.
  void sendMessage(String message) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(message);
    } else {
      print("Socket not connected (전송 불가: 연결 안됨)");
    }
  }

  /// 연결을 종료합니다.
  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _isConnected = false;
    }
  }
}
