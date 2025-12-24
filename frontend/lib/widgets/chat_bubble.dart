import 'package:flutter/material.dart';
import 'dart:async';

class ChatBubble extends StatefulWidget {
  final String message;
  final bool isAnalyzing;

  const ChatBubble({
    Key? key, 
    required this.message,
    required this.isAnalyzing,
  }) : super(key: key);

  @override
  _ChatBubbleState createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  String _displayedMessage = "";
  Timer? _typingTimer;
  int _charIndex = 0;

  @override
  void didUpdateWidget(ChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      _startTypingAnimation();
    }
  }

  @override
  void initState() {
    super.initState();
    _startTypingAnimation();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    super.dispose();
  }

  void _startTypingAnimation() {
    _typingTimer?.cancel();
    _charIndex = 0;
    _displayedMessage = "";
    
    // 빈 메시지거나 분석 중이 아니면 타이핑 스킵
    if (widget.message.isEmpty || !widget.isAnalyzing) {
       setState(() {
         _displayedMessage = widget.message;
       });
       return;
    }

    _typingTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_charIndex < widget.message.length) {
        setState(() {
          _displayedMessage += widget.message[_charIndex];
          _charIndex++;
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 말풍선 본체
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
              border: Border.all(color: Colors.indigo.shade100, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.isAnalyzing)
                   const Text(
                     "대기 중...", 
                     style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)
                   ),
                if (!widget.isAnalyzing) const SizedBox(height: 5),
                
                Text(
                  _displayedMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16, 
                    fontWeight: FontWeight.w600, 
                    color: Colors.black87,
                    height: 1.4
                  ),
                ),
              ],
            ),
          ),
          // 말풍선 꼬리 (Triangle)
          Transform.translate(
            offset: const Offset(0, -1),
            child: CustomPaint(
              size: const Size(20, 10),
              painter: TrianglePainter(strokeColor: Colors.indigo.shade100, paintingStyle: PaintingStyle.fill, fillColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class TrianglePainter extends CustomPainter {
  final Color strokeColor;
  final PaintingStyle paintingStyle;
  final Color fillColor;

  TrianglePainter({this.strokeColor = Colors.black, this.paintingStyle = PaintingStyle.stroke, this.fillColor = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
    
    final borderPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
      
    // 꼬리 테두리 (위쪽은 뚫려있어야 자연스러움)
    final borderPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
      
    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
