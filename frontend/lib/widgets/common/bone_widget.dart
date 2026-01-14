import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/design_system.dart';

class BoneWidget extends StatelessWidget {
  final String text;
  final double fontSize;
  final double paddingHorizontal;
  final double paddingVertical;

  const BoneWidget({
    super.key, 
    required this.text,
    this.fontSize = 18,
    this.paddingHorizontal = 40,
    this.paddingVertical = 12,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BoneShapePainter(),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: paddingVertical),
        child: Text(
          text,
          style: AppTextStyles.title.copyWith(
            fontSize: fontSize,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _BoneShapePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    final shadowPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.15) // Slightly stronger warm shadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final double boneEndRadius = size.height / 1.8; // Adjusted propotion
    
    // Draw connections (center rectangle part)
    final Rect body = Rect.fromLTWH(
      boneEndRadius * 0.8, 
      size.height * 0.15, 
      size.width - (boneEndRadius * 1.6), 
      size.height * 0.7
    );
    final Path path = Path()..addRect(body);

    // Draw 4 knots (the ends of the bone)
    // Left Top
    path.addOval(Rect.fromCircle(center: Offset(boneEndRadius, boneEndRadius * 0.7), radius: boneEndRadius * 0.7));
    // Left Bottom
    path.addOval(Rect.fromCircle(center: Offset(boneEndRadius, size.height - (boneEndRadius * 0.7)), radius: boneEndRadius * 0.7));
    
    // Right Top
    path.addOval(Rect.fromCircle(center: Offset(size.width - boneEndRadius, boneEndRadius * 0.7), radius: boneEndRadius * 0.7));
    // Right Bottom
    path.addOval(Rect.fromCircle(center: Offset(size.width - boneEndRadius, size.height - (boneEndRadius * 0.7)), radius: boneEndRadius * 0.7));

    canvas.drawPath(path.shift(const Offset(0, 3)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
