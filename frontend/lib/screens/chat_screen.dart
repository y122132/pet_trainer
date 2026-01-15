// frontend/lib/screens/chat_screen.dart
import 'dart:async';
import 'dart:convert';
import 'battle_page.dart'; 
import '../api_config.dart';
import 'package:flutter/material.dart';
import 'package:pet_trainer_frontend/config/theme.dart';
import 'package:pet_trainer_frontend/services/chat_service.dart';
import 'package:pet_trainer_frontend/services/auth_service.dart';
import 'package:provider/provider.dart';
import 'package:pet_trainer_frontend/providers/chat_provider.dart';
import 'package:http/http.dart' as http;
import '../providers/battle_provider.dart'; 
import 'package:intl/date_symbol_data_local.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/design_system.dart';

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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.toUsername, style: GoogleFonts.jua(color: AppColors.textMain, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surface.withOpacity(0.8),
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textMain),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              itemCount: messages.length,
              itemBuilder: (context, i) {
                final msg = messages[i];
                final currentMsgDate = msg['created_at'];

                bool isMe = msg['from_user_id'] == widget.myId;
                bool showDateDivider = false;
                if (i == 0) {
                  showDateDivider = true;
                } else {
                  DateTime prevDate = DateTime.parse(messages[i - 1]['created_at']).toLocal();
                  DateTime currDate = DateTime.parse(msg['created_at']).toLocal();
                  
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMe) _buildTimeText(msg['created_at']),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: isMe ? AppColors.secondary : Colors.white, // Soft Salmon for me, White for others
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(4),
                  bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Text(
                msg['message'] ?? "",
                style: GoogleFonts.jua(
                  color: isMe ? Colors.white : AppColors.textMain,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (!isMe) _buildTimeText(msg['created_at']),
        ],
      ),
    );
  }

  Widget _buildTimeText(String? isoString) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(
        _formatTime(isoString), 
        style: GoogleFonts.jua(fontSize: 10, color: AppColors.textSub)
      ),
    );
  }

  Widget _buildDateDivider(String dateStr) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.border.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _formatDate(dateStr),
          style: GoogleFonts.jua(color: AppColors.textMain, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildInviteMessage(Map<String, dynamic> msg, bool isMe) {
     return Align(
       alignment: Alignment.center,
       child: Container(
          margin: const EdgeInsets.symmetric(vertical: 20),
          padding: const EdgeInsets.all(20),
          width: 260,
          decoration: BoxDecoration(
             color: Colors.white,
             borderRadius: BorderRadius.circular(24),
             border: Border.all(color: AppColors.accent, width: 2),
             boxShadow: AppDecorations.softShadow,
          ),
          child: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.sports_kabaddi, color: AppColors.accent, size: 32),
                ),
                const SizedBox(height: 12),
                Text(
                  msg['message'] ?? "대결 신청이 도착했습니다!", 
                  style: GoogleFonts.jua(color: AppColors.textMain, fontWeight: FontWeight.bold, fontSize: 16), 
                  textAlign: TextAlign.center
                ),
                const SizedBox(height: 16),
                if (!isMe)
                SizedBox(
                   width: double.infinity,
                   child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary, 
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 12)
                      ),
                      onPressed: () {
                         final roomId = msg['room_id'];
                         if (roomId != null) {
                             Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChangeNotifierProvider(
                                  create: (_) => BattleProvider()..setRoomId(roomId),
                                  child: const BattleView(),
                                ),
                              ),
                            );
                         }
                      },
                      child: const Text("도전 받아들이기!", style: TextStyle(fontWeight: FontWeight.bold)),
                   ),
                )
                else
                 Text("상대방의 수락을 기다리는 중...", style: GoogleFonts.jua(color: AppColors.textSub, fontSize: 12))
             ],
          ),
       ),
     );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          )
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _msgController,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: GoogleFonts.jua(color: AppColors.textMain),
                  decoration: InputDecoration(
                    hintText: "메시지를 입력하세요...",
                    hintStyle: GoogleFonts.jua(color: AppColors.textSub),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _send,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}