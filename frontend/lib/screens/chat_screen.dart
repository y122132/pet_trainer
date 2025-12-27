import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import '../api_config.dart'; // [New]
import '../config/theme.dart'; // [New]

class ChatScreen extends StatefulWidget {
  final int myId;
  final int toUserId;
  final String toUsername;

  // myId는 UserListScreen에서 전달받음
  const ChatScreen({super.key, required this.myId, required this.toUserId, required this.toUsername});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late WebSocketChannel _channel;
  final _msgController = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // AppConfig를 사용하여 WebSocket 주소 생성
    // 주소 형식: ws://HOST:PORT/v1/chat/ws/chat/{myId}
    final url = AppConfig.chatSocketUrl(widget.myId);
    print("Connecting to Chat WebSocket: $url");
    _channel = WebSocketChannel.connect(Uri.parse(url));
    
    // [Fix] StreamBuilder 대신 직접 Listen하여 데이터 중복 처리 방지
    _channel.stream.listen((data) {
      _onMessageReceived(data);
    }, onError: (error) {
      print("WebSocket Error: $error");
    }, onDone: () {
      print("WebSocket Closed");
    });
  }

  void _onMessageReceived(dynamic data) {
    try {
      final decoded = jsonDecode(data);
      if (mounted) {
        setState(() {
          messages.add(decoded);
        });
        _scrollToBottom();
      }
    } catch (e) {
      print("Message Parse Error: $e");
    }
  }
  
  @override
  void dispose() {
    _channel.sink.close();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    if (_msgController.text.trim().isNotEmpty) {
      final text = _msgController.text.trim();
      final data = {"to_user_id": widget.toUserId, "message": text};
      
      try {
        _channel.sink.add(jsonEncode(data));
        // 내 화면에 메시지 즉시 추가 (낙관적 UI 업데이트)
        setState(() => messages.add({"from_user_id": widget.myId, "message": text}));
        _msgController.clear();
        _scrollToBottom();
      } catch (e) {
        print("Send Error: $e");
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("메시지 전송 실패")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background, // e.g. Navy background
      appBar: AppBar(
        title: Text(widget.toUsername, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.navy, 
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, i) {
                final msg = messages[i];
                bool isMe = msg['from_user_id'] == widget.myId;
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                    decoration: BoxDecoration(
                      color: isMe ? AppColors.cyberYellow : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
                        bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
                      ),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]
                    ),
                    child: Text(
                      msg['message'] ?? '',
                      style: TextStyle(color: isMe ? AppColors.navy : Colors.black87, fontSize: 16),
                    ),
                  ),
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      color: Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _msgController,
                decoration: InputDecoration(
                  hintText: "메시지를 입력하세요...",
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: AppColors.navy,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}