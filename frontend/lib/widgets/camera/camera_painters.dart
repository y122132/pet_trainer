import 'package:flutter/material.dart';
import 'dart:math' as math;

// YOLO COCO Class ID Map
const Map<int, String> yoloClasses = {
  0: 'Person',
  15: 'Cat',
  16: 'Dog',
  28: 'Handbag',
  29: 'Frisbee',
  32: 'Ball',
  39: 'Bottle',
  41: 'Cup',
  45: 'Bowl',
  46: 'Banana',
  47: 'Apple',
  48: 'Sandwich',
  49: 'Orange',
  50: 'Broccoli',
  51: 'Carrot',
  77: 'Teddy',
};

// Bounding Box Visualizer
class DebugBoxPainter extends CustomPainter {
  final List<dynamic> bbox; // [x1, y1, x2, y2]
  final bool isFrontCamera;
  final double imgRatio; // Screen/Texture processing ratio

  DebugBoxPainter({required this.bbox, required this.isFrontCamera, required this.imgRatio});

  @override
  void paint(Canvas canvas, Size size) {
    if (bbox.isEmpty) return;

    double screenRatio = size.width / size.height;
    
    // Correct logic for finding texture size
    double effectiveImgRatio = imgRatio;
    if (effectiveImgRatio > 1.0 && size.width < size.height) {
        effectiveImgRatio = 1.0 / effectiveImgRatio; 
    }
    
    double renderW, renderH;
    if (screenRatio > effectiveImgRatio) {
       renderW = size.width;
       renderH = size.width / effectiveImgRatio;
    } else {
       renderH = size.height;
       renderW = size.height * effectiveImgRatio;
    }
    
    double dx = (size.width - renderW) / 2.0;
    double dy = (size.height - renderH) / 2.0;

    final paintPet = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
      
    final paintProp = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    List<dynamic> targets = [];
    if (bbox.isNotEmpty) {
        if (bbox[0] is List) {
           targets = bbox;
        } else if (bbox.length >= 4) {
           targets = [bbox];
       }
    }

    for (var box in targets) {
      if (box.length < 4) continue;

      double nx1 = (box[0] as num).toDouble();
      double ny1 = (box[1] as num).toDouble();
      double nx2 = (box[2] as num).toDouble();
      double ny2 = (box[3] as num).toDouble();

      double x1, x2;
      if (isFrontCamera) {
         double rx1 = (1.0 - nx2) * renderW + dx;
         double rx2 = (1.0 - nx1) * renderW + dx;
         x1 = rx1; x2 = rx2;
      } else {
         x1 = nx1 * renderW + dx;
         x2 = nx2 * renderW + dx;
      }
      double y1 = ny1 * renderH + dy;
      double y2 = ny2 * renderH + dy;

      final rect = Rect.fromLTRB(x1, y1, x2, y2);
      
      String debugInfo = "";
      Paint currentPaint = paintProp;
      
      if (box.length > 5) {
         int cls = (box[5] as num).toInt();
         int conf = ((box[4] as num) * 100).toInt();
         
         String name = yoloClasses[cls] ?? "ID:$cls";
         
         if (cls == 15 || cls == 16) {
             currentPaint = paintPet;
             debugInfo = "$name $conf%";
         } else {
             currentPaint = paintProp;
             debugInfo = "$name $conf%";
         }
      }
      
      canvas.drawRect(rect, currentPaint);
      
      final textPainter = TextPainter(
        text: TextSpan(
          text: debugInfo, 
          style: TextStyle(
            color: currentPaint.color, 
            fontSize: 14, 
            fontWeight: FontWeight.bold, 
            backgroundColor: Colors.black54
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x1, y1 - 20));
    }
  }

  @override
  bool shouldRepaint(covariant DebugBoxPainter oldDelegate) {
    return oldDelegate.bbox != bbox || oldDelegate.imgRatio != imgRatio;
  }
}

// Skeleton Painter
class PosePainter extends CustomPainter {
  final List<dynamic> keypoints;
  final String feedback;
  final bool isFrontCamera;
  final double imgRatio;

  PosePainter({
    required this.keypoints,
    required this.feedback,
    required this.isFrontCamera,
    required this.imgRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (keypoints.isEmpty) return;

    final Color color = feedback.isEmpty || feedback == "no_action" ? Colors.redAccent : Colors.greenAccent;
    
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.0 
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0;

    double screenRatio = size.width / size.height;
    double effectiveImgRatio = imgRatio;
    if (effectiveImgRatio > 1.0 && size.width < size.height) {
        effectiveImgRatio = 1.0 / effectiveImgRatio; 
    }
    
    double renderW, renderH;
    if (screenRatio > effectiveImgRatio) {
       renderW = size.width;
       renderH = size.width / effectiveImgRatio;
    } else {
       renderH = size.height;
       renderW = size.height * effectiveImgRatio;
    }
    
    double dx = (size.width - renderW) / 2.0;
    double dy = (size.height - renderH) / 2.0;

    List<Offset> points = [];

    for (var kp in keypoints) {
      if (kp is List && kp.length >= 2) {
        double normX = (kp[0] as num).toDouble();
        double normY = (kp[1] as num).toDouble();
        
        double finalX;
        if (isFrontCamera) {
             finalX = (1.0 - normX) * renderW + dx;
        } else {
             finalX = normX * renderW + dx;
        }
        double finalY = normY * renderH + dy;
        
        points.add(Offset(finalX, finalY));
      }
    }

    final connections = [
      [11, 13], [13, 15], [12, 14], [14, 16], [11, 12], [5, 6], [5, 11], [6, 12], 
      [5, 7], [7, 9], [6, 8], [8, 10],
    ];

    for (var conn in connections) {
      if (conn[0] < points.length && conn[1] < points.length) {
        canvas.drawLine(points[conn[0]], points[conn[1]], linePaint);
      }
    }
    
    for (var point in points) {
      canvas.drawCircle(point, 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.keypoints != keypoints || oldDelegate.feedback != feedback || oldDelegate.imgRatio != imgRatio;
  }
}

class ConfettiPainter extends CustomPainter {
  final List<ConfettiParticle> particles;
  ConfettiPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (var p in particles) {
      final paint = Paint()..color = p.color;
      canvas.drawCircle(Offset(p.x * size.width, p.y * size.height), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ConfettiPainter oldDelegate) => true;
}

class ConfettiParticle {
  double x = 0.5, y = 0.5, vx = 0, vy = 0, size = 5;
  Color color = Colors.red;
  
  ConfettiParticle() {
    math.Random r = math.Random();
    x = 0.5;
    y = 0.4;
    vx = (r.nextDouble() - 0.5) * 0.05;
    vy = (r.nextDouble() - 0.5) * 0.05 - 0.02;
    size = r.nextDouble() * 5 + 3;
    color = Color.fromARGB(255, r.nextInt(255), r.nextInt(255), r.nextInt(255));
  }
  
  void update() {
    x += vx;
    y += vy;
    vy += 0.002;
  }
}
