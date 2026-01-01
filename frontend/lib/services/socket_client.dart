import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:pet_trainer_frontend/api_config.dart';

import 'package:pet_trainer_frontend/services/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart'; // [New]

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
      // [추가] 기기에 저장된 실제 유저 ID 가져오기
      final storage = FlutterSecureStorage();
      final String? userId = await storage.read(key: 'user_id');

      // [New] 위치 정보 가져오기 (실패 시 기본값 없이 보냄 -> 백엔드에서 처리)
      String locQuery = "";
      try {
        Position position = await _determinePosition();
        locQuery = "&lat=${position.latitude}&lon=${position.longitude}";
        print("Location Found: ${position.latitude}, ${position.longitude}");
      } catch (e) {
        print("Location Error (Permission or Service): $e");
      }

      // URL 쿼리 파라미터 구성 (하드코딩된 /1 대신 /$userId 사용)
      final uri = Uri.parse('$_wsUrl/$userId?pet_type=$petType&difficulty=$difficulty&mode=$mode$locQuery');
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

  // [New] 위치 권한 요청 및 좌표 획득 헬퍼
  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. 위치 서비스 활성화 여부 확인
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    // 2. 권한 확인
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied, we cannot request permissions.');
    } 

    // 3. 현재 위치 가져오기
    return await Geolocator.getCurrentPosition();
  }

  /// 메시지(문자열 또는 바이너리)를 서버로 전송합니다.
  void sendMessage(dynamic message) {
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
