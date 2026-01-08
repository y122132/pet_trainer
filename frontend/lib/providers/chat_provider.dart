// frontend/lib/providers/chat_provider.dart
import 'dart:async';
import 'dart:convert';
import '../api_config.dart';
import 'package:flutter/material.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ChatProvider extends ChangeNotifier {
  WebSocketChannel? _channel;
  
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  int? _currentUserId;

  int? _activeChatUserId;
  int? get activeChatUserId => _activeChatUserId;

  Map<int, bool> _onlineStatus = {};
  Map<int, bool> get onlineStatus => _onlineStatus;

  Map<int, int> _unreadCounts = {};
  Map<int, int> get unreadCounts => _unreadCounts;

  void setInitialUnreadCounts(List<dynamic> friends) {
    for (var f in friends) {
      final int friendId = f['id'];
      final int count = f['unread_count'] ?? 0;
      _unreadCounts[friendId] = count;
    }
    notifyListeners();
    debugPrint("📊 초기 안 읽은 개수 설정 완료: $_unreadCounts");
  }

  void incrementUnreadCount(int userId) {
    _unreadCounts[userId] = (_unreadCounts[userId] ?? 0) + 1;
    notifyListeners();
  }

  void resetUnreadCount(int userId) {
    _unreadCounts[userId] = 0;
    notifyListeners();
  }

  void setActiveChatUser(int? userId) {
    _activeChatUserId = userId;
    if (userId != null) {
      resetUnreadCount(userId);
    }
  }

  void clearActiveChatUser() {
    _activeChatUserId = null;
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _messageController.close();
    super.dispose();
  }

  void connect(int userId) {
    if (_isConnected && _currentUserId == userId) return;
    
    _currentUserId = userId;
    final url = AppConfig.chatSocketUrl(userId);
    debugPrint("ChatProvider: Connecting to $url");

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _isConnected = true;
      notifyListeners();

      _channel!.stream.listen((data) {
        _onMessageReceived(data);
      }, onError: (error) {
        debugPrint("ChatProvider Error: $error");
        _isConnected = false;
        notifyListeners();
      }, onDone: () {
        debugPrint("ChatProvider Closed");
        _isConnected = false;
        notifyListeners();
      });
    } catch (e) {
      debugPrint("ChatProvider Connection Failed: $e");
      _isConnected = false;
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _currentUserId = null;
    _onlineStatus.clear();  
    _unreadCounts.clear();    
    _activeChatUserId = null; 
    
    debugPrint("🧹 ChatProvider: 소켓 연결 해제 및 모든 데이터 초기화 완료");
    notifyListeners();
  }

  void _onMessageReceived(dynamic data) {
    try {
      final decoded = jsonDecode(data);

      if (decoded['type'] == 'INITIAL_ONLINE_LIST') {
        List<dynamic> userIds = decoded['user_ids'];
        for (var id in userIds) {
          _onlineStatus[id as int] = true;
        }
        debugPrint("📋 초기 온라인 명단 수신: $userIds");
        notifyListeners();
        return;
      }

      if (decoded['type'] == 'USER_STATUS') {
        int uid = decoded['user_id'];
        bool isOnline = decoded['online'];
        _onlineStatus[uid] = isOnline; 
        debugPrint("👤 유저 $uid 상태 변경 수신: ${isOnline ? '온라인' : '오프라인'}");
        notifyListeners();
        return; 
      }

      if (decoded['type'] == 'CHAT_NOTIFICATION') {
        final int senderId = decoded['from_user_id'];
        debugPrint("🔔 알림 수신: sender=$senderId, current=$_currentUserId, activeChat=$_activeChatUserId");

        if (_activeChatUserId != senderId) {
          // [Fix] 내가 보낸 메시지는 알림 띄우지 않음
          if (senderId == _currentUserId) {
             debugPrint("🔔 내가 보낸 메시지라 알림 생략 ($senderId)");
          } else {
             debugPrint("🔔 다른 사람에게 온 메시지라 팝업을 띄웁니다.");
             incrementUnreadCount(senderId);
             
             showSimpleNotification(
               Text("${decoded['sender_nickname']}님의 메시지", 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
               subtitle: Text(decoded['message'] ?? ""),
               background: Colors.indigoAccent,
               duration: const Duration(seconds: 3),
             );
          }
        } else {
          debugPrint("💬 현재 채팅 중인 상대이므로 팝업을 생략합니다. (Active: $_activeChatUserId)");
        }
      }
      _messageController.add(decoded);
    } catch (e) {
      debugPrint("ChatProvider Parse Error: $e");
    }
  }

  void sendMessage(int toUserId, String message) {
    if (_channel == null || !_isConnected || _currentUserId == null) return;

    final data = {
      "to_user_id": toUserId, 
      "message": message
    };
    _channel!.sink.add(jsonEncode(data));
  }
}
