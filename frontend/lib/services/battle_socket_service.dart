// frontend/lib/services/battle_socket_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';

class BattleSocketService {
  WebSocketChannel? _channel;
  final StreamController<dynamic> _messageController = StreamController<dynamic>.broadcast();
  
  Stream<dynamic> get stream => _messageController.stream;
  Stream<dynamic> get messageStream => _messageController.stream;
  
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  // Reconnection Config
  Timer? _reconnectTimer;
  int _retryCount = 0;
  final int _maxRetries = 5;
  String? _lastUrl;
  
  Function(bool)? _connectionStatusCallback;

  void setConnectionListener(Function(bool) callback) {
    _connectionStatusCallback = callback;
  }

  void connect(String url) {
    debugPrint("\n🌐 [BattleSocket] connect 호출됨!");
    debugPrint("🚩 전달된 최종 URL: $url");
    _lastUrl = url;
    _retryCount = 0;
    _attemptConnect();
  }

  void _attemptConnect() {
    if (_lastUrl == null) return;
    
    _cleanUpSocket(); // Ensure clean state
    
    debugPrint("[BattleSocket] Connecting to $_lastUrl (Attempt ${_retryCount + 1})");
    
    try {
      final uri = Uri.parse(_lastUrl!);
      debugPrint("🚩 파싱된 URI: $uri");

      _channel = WebSocketChannel.connect(Uri.parse(_lastUrl!));
      _isConnected = true;
      _connectionStatusCallback?.call(true);
      _retryCount = 0; // Reset on success (optimistic)

      _channel!.stream.listen(
        (message) {
          debugPrint("📥 [BattleSocket] 서버 원시 메시지 수신: $message");
          _messageController.add(message);
        },
        onError: (error) {
          debugPrint("❌ [BattleSocket] 스트림 에러 발생: $error");
          _handleDisconnect();
        },
        onDone: () {
          debugPrint("🔌 [BattleSocket] 서버에 의해 연결이 종료되었습니다. (onDone)");
          _handleDisconnect();
        },
      );
    } catch (e) {
      debugPrint("⚠️ [BattleSocket] 연결 예외 발생: $e");
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    if (!_isConnected && _retryCount >= _maxRetries) return; // Already disconnected/maxed out
    
    _isConnected = false;
    _connectionStatusCallback?.call(false);
    _cleanUpSocket();
    
    if (_retryCount < _maxRetries) {
      // Exponential Backoff: 1s, 2s, 4s, 8s, 16s
      int delay = pow(2, _retryCount).toInt();
      debugPrint("[BattleSocket] ${delay}초 후 재연결 시도 예정...");
      
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(seconds: delay), () {
        _retryCount++;
        _attemptConnect();
      });
    } else {
      debugPrint("[BattleSocket] 최대 재연결 시도 횟수 초과. 연결 종료.");
    }
  }

  void sendMessage(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      final jsonStr = jsonEncode(data);
      debugPrint("📤 [BattleSocket] 메시지 전송: $jsonStr");
      _channel!.sink.add(jsonEncode(data));
    } else {
      debugPrint("⚠️ [BattleSocket] 전송 실패: 연결되지 않음.");
    }
  }

  void _cleanUpSocket() {
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    debugPrint("🧹 [BattleSocket] 서비스 종료 (dispose)");
    _reconnectTimer?.cancel();
    _cleanUpSocket();
    _messageController.close();
  }
  void disconnect() {
    _reconnectTimer?.cancel(); // 재연결 타이머가 있다면 중지
    _channel?.sink.close();    // 소켓 연결 닫기
    _channel = null;
    _isConnected = false;
    debugPrint("🔌 [BattleSocket] 연결이 명시적으로 종료되었습니다.");
  }
}
