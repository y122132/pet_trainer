import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

class ChatScreen extends StatefulWidget {
  final int myId;
  final int toUserId;
  final String toUsername;

  const ChatScreen({super.key, required this.myId, required this.toUserId, required this.toUsername});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late WebSocketChannel _channel;
  final _msgController = TextEditingController();
  List<Map<String, dynamic>> messages = [];

  @override
  void initState() {
    super.initState();
    _channel = WebSocketChannel.connect(
      Uri.parse('ws://localhost:8000/chat/ws/chat/${widget.myId}'),
    );
  }

  void _send() {
    if (_msgController.text.isNotEmpty) {
      final data = {"to_user_id": widget.toUserId, "message": _msgController.text};
      _channel.sink.add(jsonEncode(data));
      setState(() => messages.add({"from_user_id": widget.myId, "message": _msgController.text}));
      _msgController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.toUsername)), // 상대방 닉네임 표시
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: _channel.stream,
              builder: (context, snapshot) {
                if (snapshot.hasData) messages.add(jsonDecode(snapshot.data));
                return ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    bool isMe = messages[i]['from_user_id'] == widget.myId;
                    return ListTile(
                      title: Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.blue[100] : Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(messages[i]['message']),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _msgController)),
                IconButton(icon: const Icon(Icons.send), onPressed: _send),
              ],
            ),
          )
        ],
      ),
    );
  }
}