// frontend/lib/services/battle_socket_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';

class BattleSocketService {
  WebSocketChannel? _channel;
  final StreamController<dynamic> _messageController = StreamController<dynamic>.broadcast();
  
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
    _lastUrl = url;
    _retryCount = 0;
    _attemptConnect();
  }

  void _attemptConnect() {
    if (_lastUrl == null) return;
    
    _cleanUpSocket(); // Ensure clean state
    
    debugPrint("[BattleSocket] Connecting to $_lastUrl (Attempt ${_retryCount + 1})");
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_lastUrl!));
      _isConnected = true;
      _connectionStatusCallback?.call(true);
      _retryCount = 0; // Reset on success (optimistic)

      _channel!.stream.listen(
        (message) {
          _messageController.add(message);
        },
        onError: (error) {
          debugPrint("[BattleSocket] Error: $error");
          _handleDisconnect();
        },
        onDone: () {
          debugPrint("[BattleSocket] Closed.");
          _handleDisconnect();
        },
      );
    } catch (e) {
      debugPrint("[BattleSocket] Connect Exception: $e");
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
      debugPrint("[BattleSocket] Reconnecting in ${delay}s...");
      
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(seconds: delay), () {
        _retryCount++;
        _attemptConnect();
      });
    } else {
      debugPrint("[BattleSocket] Max retries reached.");
    }
  }

  void sendMessage(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(data));
    } else {
      debugPrint("[BattleSocket] Cannot send, disconnected.");
    }
  }

  void _cleanUpSocket() {
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
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
