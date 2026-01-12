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
  List<dynamic> output, 
  int numClasses, 
  double confThreshold, 
  double iouThreshold,
  {bool isModelV8 = true, int keypointNum = 0} 
) {
  // Parsing YOLOv8 Output: [1, 4 + cls, 8400]
  // We assume 'output' is the [0]th element: [4+cls][8400] nested list or flat array appropriately handled.
  // Actually tflite_flutter returns structured tensor. Let's assume input is flattened or shaped.
  // The most standard way to handle this in Dart is accepting the TensorBuffer.
  // For simplicity, let's assume input is List<List<double>> representing [features][anchors]
  
  // Note: Output shape from TFLite for YOLOv8 is usually [1, 84, 8400] (for 80 classes)
  // Rows = Features (cx, cy, w, h, class_scores...)
  // Cols = Anchors
  
  final List<DetectionResult> detections = [];
  
  // Basic dimensions check
  if (output.isEmpty) return [];
  
  final int numFeatures = output.length;    // e.g. 4 + 80 = 84
  final int numAnchors = output[0].length;  // e.g. 8400
  
  for (int i = 0; i < numAnchors; i++) {
    // 1. Find Max Class Score
    double maxScore = 0.0;
    int maxClassIndex = -1;
    
    // Classes start from index 4
    for (int c = 0; c < numClasses; c++) {
       double score = output[4 + c][i];
       if (score > maxScore) {
         maxScore = score;
         maxClassIndex = c;
       }
    }
    
    // 2. Threshold Check
    if (maxScore < confThreshold) continue;
    
    // 3. Decode Box (cx, cy, w, h) -> (x1, y1, x2, y2)
    double cx = output[0][i];
    double cy = output[1][i];
    double w = output[2][i];
    double h = output[3][i];
    
    double x1 = cx - w / 2;
    double y1 = cy - h / 2;
    double x2 = cx + w / 2;
    double y2 = cy + h / 2;
    
    // [Fix] Do NOT clamp to 0.0-1.0 here because model outputs PIXEL coordinates (e.g. 0-640).
    // Caller (edge_detector_native) handles normalization by dividing by targetSize.
    // x1 = x1.clamp(0.0, 1.0);
    // y1 = y1.clamp(0.0, 1.0);
    // x2 = x2.clamp(0.0, 1.0);
    // y2 = y2.clamp(0.0, 1.0);
    
    // 4. Extract Keypoints (if any)
    List<double>? kpts;
    if (keypointNum > 0) {
      kpts = [];
      // Keypoints start after classes. 
      // Index = 4 + numClasses + (k * 3)
      // k*3 because x, y, conf
      int kptStartIdx = 4 + numClasses;
      
      for (int k = 0; k < keypointNum; k++) {
         double kx = output[kptStartIdx + k * 3][i];
         double ky = output[kptStartIdx + k * 3 + 1][i];
         double kc = output[kptStartIdx + k * 3 + 2][i];
         
         // Normalize Keypoint Coordinates (Assuming they are absolute in model output? No, YOLOv8 output is usually relative to input size like box cx, cy?)
         // Actually YOLOv8 export usually outputs absolute coords relative to image size.
         // Since box cx/cy were divided by input size? No, in standard export they are not normalized.
         // Wait, let's check box logic above:
         // double cx = output[0][i]; ...
         // The caller divides by targetSize later in `For loop` in `edge_detector_native.dart`: 
         // `det.box[0] / targetSize`
         // So `edge_utils` returns raw model output coordinates.
         // We should do the same for keypoints here. Caller will normalize.
         
         kpts.add(kx);
         kpts.add(ky);
         kpts.add(kc);
      }
    }
    
    detections.add(DetectionResult([x1, y1, x2, y2], maxScore, maxClassIndex, keypoints: kpts));
  }
  
  // 4. Sort by score (descending)
  detections.sort((a, b) => b.score.compareTo(a.score));
  
  // 5. NMS Loop
  final List<DetectionResult> result = [];
  while (detections.isNotEmpty) {
    final current = detections.removeAt(0);
    result.add(current);
    
    detections.removeWhere((other) {
      double iou = calculateIoU(current.box, other.box);
      return iou > iouThreshold;
    });
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
       
       buffer[pixelIndex++] = r.clamp(0, 255) / 255.0;
       buffer[pixelIndex++] = g.clamp(0, 255) / 255.0;
       buffer[pixelIndex++] = b.clamp(0, 255) / 255.0;
    }
  }
  
  return buffer;
}


