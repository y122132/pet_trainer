import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../api_config.dart';
import '../models/chat_model.dart';

class ChatService {
  WebSocketChannel? _channel;
  bool _isConnected = false;

  // 1. 웹소켓 연결
  void connect(int userId) {
    if (_isConnected) return;

    final String url = AppConfig.chatSocketUrl(userId);
    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(url));
      _isConnected = true;
      print("[CHAT] WebSocket 연결 성공: $url");
    } catch (e) {
      print("[CHAT] WebSocket 연결 실패: $e");
      _isConnected = false;
    }
  }

  // 2. 메시지 수신 스트림 (UI에서 사용)
  Stream<ChatMessage> get messages {
    if (_channel == null) return const Stream.empty();
    
    return _channel!.stream.map((data) {
      final Map<String, dynamic> json = jsonDecode(data);
      return ChatMessage.fromJson(json);
    });
  }

  // 3. 메시지 송신 (백엔드 규격: to_user_id, message)
  void sendMessage(int toUserId, String message) {
    if (_channel != null && _isConnected) {
      final payload = jsonEncode({
        "to_user_id": toUserId,
        "message": message,
      });
      _channel!.sink.add(payload);
    } else {
      print("[CHAT] 연결이 되어있지 않아 메시지를 보낼 수 없습니다.");
    }
  }

  // 4. 연결 종료
  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
    print("[CHAT] WebSocket 연결 종료");
  }
}
