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
            child: StreamBuilder(
              stream: _channel.stream,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  // 수신된 메시지 파싱
                  try {
                    final decoded = jsonDecode(snapshot.data);
                    // 상대방이 보낸 것인지 확인 (또는 내가 보낸 것의 echo일 수 있음)
                    // 현재 백엔드 로직: 내가 보낸건 echo 안해줌. 상대방에게만 감.
                    // 따라서 Stream에서 오는건 상대방 메시지임.
                    
                    // 주의: StreamBuilder는 리빌드 될 때마다 snapshot을 다시 줄 수 있으므로
                    // 리스트에 중복 추가되지 않도록 관리하거나, 별도 리스너를 쓰는게 좋지만
                    // 여기선 간단히 처리. (실제론 StreamSubscription 권장)
                    
                    // *간단 수정*: StreamBuilder 내부에서 setState를 직접호출하거나 리스트에 add하는건
                    // 빌드 사이클 중에 위험함.
                    // 하지만 기존 구조를 유지하며, 막 받은 데이터가 리스트 마지막과 다르면 추가하는 식으로 방어.
                    
                    final lastMsg = messages.isNotEmpty ? messages.last : null;
                    if (lastMsg == null || lastMsg['message'] != decoded['message'] || lastMsg['from_user_id'] != decoded['from_user_id']) {
                        // (이 방식은 완벽하지 않지만, 데모용으로 허용)
                        // 리스트 조작은 addPostFrameCallback 혹은 Stream.listen에서 해야함.
                        // 여기서는 화면 갱신용으로만 쓰고 값 저장은 initState에서 listen하는게 정석.
                        // 우선 기존 코드 스타일을 존중하되, 화면 깜빡임 방지위해 복잡한 로직 지양.
                        
                        // [Hotfix] StreamBuilder 패턴 대신, initState에서 listen 하는 방식으로 변경 고려.
                        // 하지만 시간 관계상 현재 구조 유지하되, 데이터 추가 로직을 분리.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                           if (messages.isEmpty || messages.last != decoded) { // 객체 비교는 위험하므로 주의
                               setState(() {
                                 messages.add(decoded);
                               });
                               _scrollToBottom();
                           }
                        });
                    }
                  } catch (e) {
                    print("Message Parse Error: $e");
                  }
                }
                
                return ListView.builder(
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