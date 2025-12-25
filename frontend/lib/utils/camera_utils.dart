import 'dart:typed_data';
import 'package:image/image.dart' as img;

// --- Top-level function for compute() ---
// Must be top-level or static.
Uint8List processCameraImageToJpeg(Map<String, dynamic> data) {
  final int width = data['width'];
  final int height = data['height'];
  // sensorOrientation is not directly used for YUV->RGB but for rotation decision logic passed via rotationAngle
  final List<dynamic> planes = data['planes'];
  
  // YUV Extraction
  final Uint8List yBytes = planes[0]['bytes'];
  final Uint8List uBytes = planes[1]['bytes'];
  final Uint8List vBytes = planes[2]['bytes'];
  
  final int uvRowStride = planes[1]['bytesPerRow'];
  final int uvPixelStride = planes[1]['bytesPerPixel'] ?? 1;
  
  // Create Image buffer
  final img.Image yuvImage = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int uvIndex = uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
      final int index = y * width + x;
      
      final int yValue = yBytes[index];
      final int uValue = uBytes[uvIndex];
      final int vValue = vBytes[uvIndex];

      int r = (yValue + 1.402 * (vValue - 128)).round();
      int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round();
      int b = (yValue + 1.772 * (uValue - 128)).round();

      yuvImage.setPixelRgba(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255), 255);
    }
  }
  
  // Resize (Maintain Aspect Ratio)
  // resizing to width 640. height is auto-calculated.
  img.Image resizedImage = img.copyResize(yuvImage, width: 640);

  // Rotation
  final int rotationAngle = data['rotationAngle'] ?? 0;
  if (rotationAngle != 0) {
    resizedImage = img.copyRotate(resizedImage, angle: rotationAngle);
  }

  // Encode to JPEG
  return Uint8List.fromList(img.encodeJpg(resizedImage, quality: 85));
}
