// frontend/lib/services/socket_client.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:pet_trainer_frontend/api_config.dart';
import 'package:pet_trainer_frontend/services/auth_service.dart';

// [Deleted] Unused import

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
  /// [petType]: 반려동물 종류 (예: 'dog', 'cat')
  /// [difficulty]: 난이도 ('easy', 'hard')
  /// [mode]: 훈련 모드 ('playing', 'feeding', 'interaction')
  Future<void> connect(String petType, String difficulty, String mode) async {
    if (_isConnected) return; // 이미 연결되어 있으면 무시

    try {
      // [추가] 기기에 저장된 실제 유저 ID 및 토큰 가져오기
      // Fix: Use AuthService which uses correct AndroidOptions for secure storage
      final String? userId = await AuthService().getUserId();
      final String? token = await AuthService().getToken();

      // URL 쿼리 파라미터 구성 (하드코딩된 /1 대신 /$userId 사용, 토큰 추가)
      final uri = Uri.parse('$_wsUrl/$userId?pet_type=$petType&difficulty=$difficulty&mode=$mode&token=$token');
      print("Socket Connecting to: $uri");
      
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;

      _channel!.stream.listen(
        (message) {
          print("🚩 [소켓 수신] 타입: ${message.runtimeType} / 내용: $message");
          
          try {
            String decodedMessage;
            if (message is List<int>) {
              decodedMessage = utf8.decode(message);
            } else {
              decodedMessage = message.toString();
            }

            final data = jsonDecode(decodedMessage);
            print("🔍 [파싱결과] type: ${data['type']}");

            print("🔍 [파싱결과] type: ${data['type']}");

            // [Fix] Removed redundant CHAT_NOTIFICATION logic (handled by ChatProvider)
          } catch (e) {}
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
