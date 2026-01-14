import 'package:flutter/material.dart';
import 'dart:async';
import 'package:pet_trainer_frontend/config/theme.dart';
import 'package:pet_trainer_frontend/config/design_system.dart';

class CharMessageBubble extends StatefulWidget {
  final String message;
  final bool isAnalyzing; // Used for "typing" effect or purely display

  const CharMessageBubble({
    Key? key, 
    required this.message,
    this.isAnalyzing = true, // Default to true to show typing if message changes
  }) : super(key: key);

  @override
  _CharMessageBubbleState createState() => _CharMessageBubbleState();
}

class _CharMessageBubbleState extends State<CharMessageBubble> {
  String _displayedMessage = "";
  Timer? _typingTimer;
  int _charIndex = 0;

  @override
  void didUpdateWidget(CharMessageBubble oldWidget) {
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
    
    // If empty, just clear
    if (widget.message.isEmpty) {
       if (mounted) setState(() => _displayedMessage = "");
       return;
    }

    _typingTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_charIndex < widget.message.length) {
        if (mounted) {
          setState(() {
            _displayedMessage += widget.message[_charIndex];
            _charIndex++;
          });
        }
      } else {
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Centered or positioned by parent
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Bubble Body
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                   color: Colors.black12,
                   blurRadius: 10,
                   offset: Offset(0, 4)
                )
              ],
              border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1.5),
            ),
            child: Text(
              _displayedMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14, 
                fontWeight: FontWeight.w600, 
                color: AppColors.textMain,
                height: 1.3
              ),
            ),
          ),
          // Triangle Tail
          CustomPaint(
            size: const Size(16, 8),
            painter: TrianglePainter(
               fillColor: Colors.white, 
               strokeColor: AppColors.primary.withOpacity(0.3)
            ),
          ),
        ],
      ),
    );
  }
}

class TrianglePainter extends CustomPainter {
  final Color strokeColor;
  final Color fillColor;

  TrianglePainter({this.strokeColor = Colors.grey, this.fillColor = Colors.white});

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
    
    // Border for the triangle (only sides)
    final borderPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
      
    final borderPath = Path()
      ..moveTo(0, 0) // Start top left
      ..lineTo(size.width / 2, size.height) // Tip
      ..lineTo(size.width, 0); // Top right (open top)
      
    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
