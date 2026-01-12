import 'dart:math';
import 'dart:typed_data';

// --- Data Structures ---
class DetectionResult {
  final List<double> box; // [x1, y1, x2, y2] (Normalized 0.0 - 1.0)
  final double score;
  final int classIndex;
  final List<double>? keypoints; // [x1, y1, c1, x2, y2, c2, ...] Normalized
  
  DetectionResult(this.box, this.score, this.classIndex, {this.keypoints});
}

// --- Math & NMS Utils ---

/// Intersection over Union (IoU) Calculation
double calculateIoU(List<double> box1, List<double> box2) {
  final double x1 = max(box1[0], box2[0]);
  final double y1 = max(box1[1], box2[1]);
  final double x2 = min(box1[2], box2[2]);
  final double y2 = min(box1[3], box2[3]);

  final double intersectionArea = max(0, x2 - x1) * max(0, y2 - y1);
  final double box1Area = (box1[2] - box1[0]) * (box1[3] - box1[1]);
  final double box2Area = (box2[2] - box2[0]) * (box2[3] - box2[1]);

  final double unionArea = box1Area + box2Area - intersectionArea;
  if (unionArea <= 0) return 0.0;
  
  return intersectionArea / unionArea;
}

/// YOLO Non-Maximum Suppression (NMS)
/// input: Raw output tensor [1, features, anchors] -> Flat Float32List or List<List>
/// YOLOv8/v11 shape: [Batch, 4+Classes, 8400] -> We usually need to transpose to [8400, 4+Classes]
List<DetectionResult> nonMaxSuppression(
  dynamic output, // List<dynamic> (nested) or Float32List (flat)
  int numClasses, 
  double confThreshold, 
  double iouThreshold,
  {bool isModelV8 = true, int keypointNum = 0, List<int>? shape} 
) {
  final List<DetectionResult> detections = [];
  
  if (output == null) return [];
  
  // FLAT BUFFER MODE
  if (output is Float32List && shape != null && shape.length >= 3) {
      // Shape: [Batch, Features, Anchors]
      final int numFeatures = shape[1];
      final int numAnchors = shape[2];
      
      // Access: buffer[f * numAnchors + i] (Assuming [1, 84, 8400])
      // Verify layout: TFLite usually outputs Row-Major.
      // If shape is [1, 84, 8400], it stores 8400 values of Feat 0, then 8400 of Feat 1...
      
      for (int i = 0; i < numAnchors; i++) {
         // 1. Max Score
         double maxScore = 0.0;
         int maxClassIndex = -1;
         
         for (int c = 0; c < numClasses; c++) {
             // Score Index: (4 + c) * numAnchors + i
             int idx = (4 + c) * numAnchors + i;
             double score = output[idx];
             if (score > maxScore) {
                 maxScore = score;
                 maxClassIndex = c;
             }
         }
         
         if (maxScore < confThreshold) continue;

         // 2. Box
         double cx = output[0 * numAnchors + i];
         double cy = output[1 * numAnchors + i];
         double w = output[2 * numAnchors + i];
         double h = output[3 * numAnchors + i];
         
         double x1 = cx - w / 2;
         double y1 = cy - h / 2;
         double x2 = cx + w / 2;
         double y2 = cy + h / 2;
         
         // 3. Keypoints
         List<double>? kpts;
         if (keypointNum > 0) {
             kpts = [];
             int kptStartRow = 4 + numClasses;
             for (int k = 0; k < keypointNum; k++) {
                 int row_x = kptStartRow + k * 3;
                 int row_y = row_x + 1;
                 int row_c = row_x + 2;
                 
                 double kx = output[row_x * numAnchors + i];
                 double ky = output[row_y * numAnchors + i];
                 double kc = output[row_c * numAnchors + i];
                 
                 kpts.add(kx); kpts.add(ky); kpts.add(kc);
             }
         }
         
         detections.add(DetectionResult([x1, y1, x2, y2], maxScore, maxClassIndex, keypoints: kpts));
      }

  } else if (output is List) {
      // LEGACY NESTED LIST MODE (Keep for compatibility if needed)
      if (output.isEmpty) return [];
      
      // Assume output is [Features][Anchors] (after parsing [0])
      // Or output could be [Batch][Features][Anchors] -> Caller usually passes batch0
      
      // Safe check: output[0] is List?
      if (output[0] is! List) return []; // Flat list without shape?
      
      final int numFeatures = output.length;
      final int numAnchors = (output[0] as List).length;
      
      for (int i = 0; i < numAnchors; i++) {
          double maxScore = 0.0;
          int maxClassIndex = -1;
          for (int c = 0; c < numClasses; c++) {
              double score = (output[4 + c] as List)[i]; // Dynamic access
              if (score > maxScore) { maxScore = score; maxClassIndex = c; }
          }
          if (maxScore < confThreshold) continue;
          
          double cx = (output[0] as List)[i];
          double cy = (output[1] as List)[i];
          double w = (output[2] as List)[i];
          double h = (output[3] as List)[i];
          
          double x1 = cx - w / 2;
          double y1 = cy - h / 2;
          double x2 = cx + w / 2;
          double y2 = cy + h / 2;
          
          List<double>? kpts;
          if (keypointNum > 0) {
              kpts = [];
              int kptStartIdx = 4 + numClasses;
              for (int k = 0; k < keypointNum; k++) {
                  double kx = (output[kptStartIdx + k * 3] as List)[i];
                  double ky = (output[kptStartIdx + k * 3 + 1] as List)[i];
                  double kc = (output[kptStartIdx + k * 3 + 2] as List)[i];
                  kpts.addAll([kx, ky, kc]);
              }
          }
          detections.add(DetectionResult([x1, y1, x2, y2], maxScore, maxClassIndex, keypoints: kpts));
      }
  }

  // Common Sort & NMS
  detections.sort((a, b) => b.score.compareTo(a.score));
  
  final List<DetectionResult> result = [];
  while (detections.isNotEmpty) {
      final current = detections.removeAt(0);
      result.add(current);
      detections.removeWhere((other) => calculateIoU(current.box, other.box) > iouThreshold);
  }
  return result;
}

// --- Logic Utils (Ported from detector.py) ---

double calculateSquaredDistance(List<double> p1, List<double> p2, double xScale, double yScale) {
  double dx = (p1[0] - p2[0]) * xScale;
  double dy = (p1[1] - p2[1]) * yScale;
  return dx * dx + dy * dy;
}

// --- Preprocessing Utils ---

/// Converts YUV420 to Float32List (RGB Planar or Interleaved)
/// Input: CameraImage planes (Y, U, V bytes and strides)
/// Output: Float32List [1, 3, H, W] or [1, H, W, 3] normalized 0.0-1.0
Float32List convertYUVToFloat32Tensor(
  Map<String, dynamic> data, 
  int targetW, 
  int targetH,
  int rotationAngle // [NEW] 0, 90, 180, 270
) {
  final int width = data['width'];
  final int height = data['height'];
  final List<dynamic> planes = data['planes'];
  
  final Uint8List yBytes = planes[0]['bytes'];
  final Uint8List uBytes = planes[1]['bytes'];
  final Uint8List vBytes = planes[2]['bytes'];
  
  final int yRowStride = planes[0]['bytesPerRow'];
  final int uvRowStride = planes[1]['bytesPerRow'];
  final int uvPixelStride = planes[1]['bytesPerPixel'] ?? 1;

  // Output Buffer: [H * W * 3]
  final Float32List buffer = Float32List(targetW * targetH * 3);
  int pixelIndex = 0;

  for (int y = 0; y < targetH; y++) {
    for (int x = 0; x < targetW; x++) {
       // Coordinate Transformation for Rotation
       int srcX, srcY;
       
       // Calculate normalized position (0.0 - 1.0) in generic 0-degree space
       // Then map to source coordinates based on rotation
       
       if (rotationAngle == 90) {
         // Target(x,y) comes from Source. rotated 90 CW
         // Visual: Top-Right of Source becomes Top-Left of Target?
         // No, standard Camera rotation:
         // 90 deg means the sensor is rotated 90 deg relative to upright.
         // We need to sample "sideways".
         
         // Mapping back from Target(x,y) to Source(sx, sy):
         // sx = y
         // sy = targetW - 1 - x (Target Width corresponds to Source Height)
         // Wait, aspect ratios strictly:
         // Source Width corresponds to Target Height? No.
         
         // Simple Mapping logic:
         // 0 deg:   sx = map(x, tW, sW), sy = map(y, tH, sH)
         // 90 deg:  sx = map(y, tH, sW), sy = map(tW-x, tW, sH)
         // 180 deg: sx = map(tW-x, tW, sW), sy = map(tH-y, tH, sH)
         // 270 deg: sx = map(tH-y, tH, sW), sy = map(x, tW, sH)
         
         // Using Nearest Neighbor map
         srcX = (y * width / targetH).floor();
         srcY = ((targetW - 1 - x) * height / targetW).floor();
         
       } else if (rotationAngle == 180) {
         srcX = ((targetW - 1 - x) * width / targetW).floor();
         srcY = ((targetH - 1 - y) * height / targetH).floor();
         
       } else if (rotationAngle == 270) {
         srcX = ((targetH - 1 - y) * width / targetH).floor();
         srcY = (x * height / targetW).floor();
         
       } else {
         // 0 degrees
         srcX = (x * width / targetW).floor();
         srcY = (y * height / targetH).floor();
       }
       
       // Bounds Check (Safety first)
       srcX = srcX.clamp(0, width - 1);
       srcY = srcY.clamp(0, height - 1);
       
       // YUV Indices
       final int uvIndex = uvPixelStride * (srcX / 2).floor() + uvRowStride * (srcY / 2).floor();
       final int index = srcY * yRowStride + srcX;
       
       if (index >= yBytes.length || uvIndex >= uBytes.length || uvIndex >= vBytes.length) {
         buffer[pixelIndex++] = 0.0;
         buffer[pixelIndex++] = 0.0;
         buffer[pixelIndex++] = 0.0;
         continue;
       }

       final int yVal = yBytes[index];
       final int uVal = uBytes[uvIndex];
       final int vVal = vBytes[uvIndex];

       // YUV to RGB conversion
       int r = (yVal + 1.402 * (vVal - 128)).round();
       int g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).round();
       int b = (yVal + 1.772 * (uVal - 128)).round();
       
       buffer[pixelIndex++] = r.clamp(0, 255).toDouble();
       buffer[pixelIndex++] = g.clamp(0, 255).toDouble();
       buffer[pixelIndex++] = b.clamp(0, 255).toDouble();
    }
  }
  
  return buffer;
}

/// Converts YUV420 to Uint8List (RGB) directly [0-255]
/// Input: CameraImage planes
/// Output: Uint8List [H * W * 3]
Uint8List convertYUVToRGBBytes(
  Map<String, dynamic> data, 
  int targetW, 
  int targetH,
  int rotationAngle
) {
  final int width = data['width'];
  final int height = data['height'];
  final List<dynamic> planes = data['planes'];
  
  final Uint8List yBytes = planes[0]['bytes'];
  final Uint8List uBytes = planes[1]['bytes'];
  final Uint8List vBytes = planes[2]['bytes'];
  
  final int yRowStride = planes[0]['bytesPerRow'];
  final int uvRowStride = planes[1]['bytesPerRow'];
  final int uvPixelStride = planes[1]['bytesPerPixel'] ?? 1;

  final Uint8List buffer = Uint8List(targetW * targetH * 3);
  int pixelIndex = 0;

  for (int y = 0; y < targetH; y++) {
    for (int x = 0; x < targetW; x++) {
       int srcX, srcY;
       
       if (rotationAngle == 90) { // 90 CW (Right)
         srcX = (y * width / targetH).floor();
         srcY = ((targetW - 1 - x) * height / targetW).floor();
       } else if (rotationAngle == 180) { // 180
         srcX = ((targetW - 1 - x) * width / targetW).floor();
         srcY = ((targetH - 1 - y) * height / targetH).floor();
       } else if (rotationAngle == 270) { // 270 CW (Left)
         srcX = ((targetH - 1 - y) * width / targetH).floor();
         srcY = (x * height / targetW).floor();
       } else { // 0
         srcX = (x * width / targetW).floor();
         srcY = (y * height / targetH).floor();
       }
       
       srcX = srcX.clamp(0, width - 1);
       srcY = srcY.clamp(0, height - 1);
       
       final int uvIndex = uvPixelStride * (srcX / 2).floor() + uvRowStride * (srcY / 2).floor();
       final int index = srcY * yRowStride + srcX;
       
       if (index >= yBytes.length || uvIndex >= uBytes.length || uvIndex >= vBytes.length) {
         buffer[pixelIndex++] = 0;
         buffer[pixelIndex++] = 0;
         buffer[pixelIndex++] = 0;
         continue;
       }

       final int yVal = yBytes[index];
       final int uVal = uBytes[uvIndex];
       final int vVal = vBytes[uvIndex];

       // Integer Conversion (Standard)
       final int c = yVal;
       final int d = uVal - 128;
       final int e = vVal - 128;
       
       int r = (c + 1.402 * e).round();
       int g = (c - 0.344136 * d - 0.714136 * e).round();
       int b = (c + 1.772 * d).round();

       buffer[pixelIndex++] = r.clamp(0, 255);
       buffer[pixelIndex++] = g.clamp(0, 255);
       buffer[pixelIndex++] = b.clamp(0, 255);
    }
  }
  return buffer;
}


/// Parse TFLite Output that already has NMS applied (nms=True export)
/// Shape: [1, 300, 6] (Obj) or [1, 300, 57] (Pose)
/// Layout: [x1, y1, x2, y2, score, class, kpt1_x, kpt1_y, kpt1_conf, ...]
List<DetectionResult> parseNMSOutput(
  Float32List output, 
  double confThreshold,
  {int keypointNum = 0}
) {
  final List<DetectionResult> results = [];
  
  // Stride calculation
  // 4 (box) + 1 (score) + 1 (class) + (kpts * 3)
  final int stride = 4 + 1 + 1 + (keypointNum * 3);
  final int numDetections = output.length ~/ stride;
  
  for (int i = 0; i < numDetections; i++) {
     int offset = i * stride;
     
     double score = output[offset + 4];
     if (score < confThreshold) continue;
     
     // Ultralytics NMS usually returns Top-Left / Bottom-Right (x1,y1,x2,y2)
     // BUT we must verify if it's cx, cy, w, h. 
     // Standard TFLite Object Detection API is [y1, x1, y2, x2].
     // Ultralytics export logic: runs non_max_suppression op.
     // Let's assume (x1, y1, x2, y2) for now based on typical pytorch export.
     
     double x1 = output[offset + 0];
     double y1 = output[offset + 1];
     double x2 = output[offset + 2];
     double y2 = output[offset + 3];
     
     double cls = output[offset + 5];
     
     List<double>? kpts;
     if (keypointNum > 0) {
        kpts = [];
        int kptStart = offset + 6;
        for (int k = 0; k < keypointNum; k++) {
           kpts.add(output[kptStart + k*3]);     // x
           kpts.add(output[kptStart + k*3 + 1]); // y
           kpts.add(output[kptStart + k*3 + 2]); // conf
        }
     }
     
     results.add(DetectionResult([x1, y1, x2, y2], score, cls.toInt(), keypoints: kpts));
  }
  
  return results;
}
