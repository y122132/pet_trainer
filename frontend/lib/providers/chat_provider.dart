import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../api_config.dart';

class ChatProvider extends ChangeNotifier {
  WebSocketChannel? _channel;
  final List<Map<String, dynamic>> _messages = []; // For specific chat room persistence if needed
  
  // Stream controller to broadcast messages to listeners (ChatScreen, MenuPage)
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  int? _currentUserId;

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
    notifyListeners();
  }

  void _onMessageReceived(dynamic data) {
    try {
      final decoded = jsonDecode(data);
      // Broadcast to active listeners
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
