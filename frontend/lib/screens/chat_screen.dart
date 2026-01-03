// frontend/lib/screens/chat_screen.dart
import 'dart:async';
import 'dart:convert';
import 'battle_page.dart'; 
import '../api_config.dart';
import '../config/theme.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../providers/chat_provider.dart';
import '../providers/battle_provider.dart'; 
import 'package:intl/date_symbol_data_local.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ChatScreen extends StatefulWidget {
  final int myId;
  final int toUserId;
  final String toUsername;

  const ChatScreen({super.key, required this.myId, required this.toUserId, required this.toUsername});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgController = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  final ScrollController _scrollController = ScrollController();
  late StreamSubscription<Map<String, dynamic>> _chatSubscription;
  late ChatProvider _chatProvider;

  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return "";
    try {
      // ISO 문자열을 읽어서 현지 시간으로 변환
      DateTime dateTime = DateTime.parse(isoString).toLocal();
      // '2026년 1월 2일 금요일' 형태로 변환
      return DateFormat('yyyy년 M월 d일 EEEE', 'ko_KR').format(dateTime);
    } catch (e) {
      debugPrint("Date Format Error: $e");
      return "";
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return "";
    try {
      DateTime dateTime = DateTime.parse(isoString).toLocal();
      return DateFormat('a h:mm', 'ko_KR').format(dateTime);
    } catch (e) {
      return "";
    }
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatProvider = Provider.of<ChatProvider>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    _markMessagesAsRead();
    _loadHistory();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatProvider.connect(widget.myId);
      _chatProvider.setActiveChatUser(widget.toUserId);
    });

    _chatSubscription = Provider.of<ChatProvider>(context, listen: false)
        .messageStream.listen((data) {
      _onMessageReceived(data);
    });
  }

  Future<void> _markMessagesAsRead() async {
    try {
      await http.post(
        Uri.parse('${AppConfig.baseUrl}/chat/read/${widget.toUserId}?current_user_id=${widget.myId}'),
      );
      // 내 로컬 ChatProvider의 미확인 알림 개수도 여기서 즉시 초기화
      if (mounted) {
        Provider.of<ChatProvider>(context, listen: false).resetUnreadCount(widget.toUserId);
      }
    } catch (e) {
      debugPrint("Read Update Error: $e");
    }
  }

  Future<void> _loadHistory() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/chat/history/${widget.toUserId}?current_user_id=${widget.myId}'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> history = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          messages = history.cast<Map<String, dynamic>>();
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("History Load Error: $e");
    }
  }

  void _onMessageReceived(Map<String, dynamic> decoded) {
    if (mounted) {
      final int? senderId = decoded['from_user_id'];
      
      if (senderId == widget.toUserId || senderId == widget.myId) {
        setState(() {
          messages.add(decoded);
        });
        _scrollToBottom();
      } else {
        debugPrint("📩 다른 유저(${senderId})에게 온 메시지라 이 화면에는 표시하지 않습니다.");
      }
    }
  }
  
  @override
  void dispose() {
    _chatProvider.clearActiveChatUser();
    _chatSubscription.cancel();
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
      final nowStr = DateTime.now().toIso8601String();
      
      try {
        Provider.of<ChatProvider>(context, listen: false).sendMessage(widget.toUserId, text);
        setState(() => messages.add({
          "from_user_id": widget.myId, 
          "message": text,
          "created_at": nowStr,
          }));
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
                final currentMsgDate = msg['created_at'];

                bool isMe = msg['from_user_id'] == widget.myId;
                bool showDateDivider = false;
                if (i == 0) {
                  showDateDivider = true; // 첫 메시지는 무조건 날짜 표시
                } else {
                  DateTime prevDate = DateTime.parse(messages[i - 1]['created_at']).toLocal();
                  DateTime currDate = DateTime.parse(msg['created_at']).toLocal();
                  
                  // 연, 월, 일이 하나라도 다르면 날짜가 바뀐 것임
                  if (prevDate.year != currDate.year || 
                      prevDate.month != currDate.month || 
                      prevDate.day != currDate.day) {
                    showDateDivider = true;
                  }
                }
                
                return Column(
                  children: [
                    if (showDateDivider) _buildDateDivider(msg['created_at']),

                    if (msg['type'] == 'BATTLE_INVITE') 
                      _buildInviteMessage(msg, isMe)
                    else
                      _buildMessageBubble(msg, isMe),
                  ],
                );

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

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMe) _buildTimeText(msg['created_at']), // 내 메시지면 시간 먼저
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
            decoration: BoxDecoration(
              color: isMe ? AppColors.cyberYellow : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(msg['message'] ?? ""),
          ),
          if (!isMe) _buildTimeText(msg['created_at']), // 상대 메시지면 나중에 시간
        ],
      ),
    );
  }

  Widget _buildTimeText(String? isoString) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Text(_formatTime(isoString), style: const TextStyle(fontSize: 10, color: Colors.grey)),
    );
  }

  Widget _buildDateDivider(String dateStr) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _formatDate(dateStr),
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildInviteMessage(Map<String, dynamic> msg, bool isMe) {
     return Align(
       alignment: Alignment.center, // Center system messages
       child: Container(
          margin: const EdgeInsets.symmetric(vertical: 15),
          padding: const EdgeInsets.all(16),
          width: 250,
          decoration: BoxDecoration(
             color: Colors.black87,
             borderRadius: BorderRadius.circular(16),
             border: Border.all(color: AppColors.cyberYellow, width: 2),
             boxShadow: [BoxShadow(color: AppColors.cyberYellow.withOpacity(0.3), blurRadius: 10)]
          ),
          child: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
                const Icon(Icons.sports_kabaddi, color: AppColors.cyberYellow, size: 30),
                const SizedBox(height: 8),
                Text(msg['message'] ?? "Battle Invitation", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                if (!isMe) // 내가 보낸건 버튼 안보임
                SizedBox(
                   width: double.infinity,
                   child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
                      onPressed: () {
                         final roomId = msg['room_id'];
                         if (roomId != null) {
                            // Join Battle
                             Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChangeNotifierProvider( // Using Provider
                                  create: (_) => BattleProvider()..setRoomId(roomId),
                                  child: const BattleView(),
                                ),
                              ),
                            );
                         }
                      },
                      child: const Text("FIGHT! (입장)", style: TextStyle(fontWeight: FontWeight.bold)),
                   ),
                )
                else
                 const Text("Waiting for opponent...", style: TextStyle(color: Colors.grey, fontSize: 12))
             ],
          ),
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
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.text,
                enableInteractiveSelection: true,
                selectionControls: desktopTextSelectionControls,
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