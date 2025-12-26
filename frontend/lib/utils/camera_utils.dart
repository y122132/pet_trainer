import 'dart:typed_data';
import 'package:image/image.dart' as img;

// --- Top-level function for compute() ---
// Must be top-level or static.
Uint8List resizeAndCompressImage(Map<String, dynamic> data) {
  final int width = data['width'];
  final int height = data['height'];
  // sensorOrientation is not directly used for YUV->RGB but for rotation decision logic passed via rotationAngle
  final List<dynamic> planes = data['planes'];
  
  // YUV Extraction
  final Uint8List yBytes = planes[0]['bytes'];
  final Uint8List uBytes = planes[1]['bytes'];
  final Uint8List vBytes = planes[2]['bytes'];
  
  // [Robust Stride Calculation]
  // Calculate stride from buffer size if reported stride looks suspicious (equals width but buffer is larger).
  int yRowStride = planes[0]['bytesPerRow'];
  if (yBytes.length > width * height && yRowStride <= width) {
    yRowStride = (yBytes.length / height).round();
  }

  int uvRowStride = planes[1]['bytesPerRow'];
  final int uvPixelStride = planes[1]['bytesPerPixel'] ?? 1;
  
  // Create Image buffer
  final img.Image yuvImage = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int uvIndex = uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
      
      // [Fix] Use yRowStride instead of width. 
      // Camera sensors often add padding bytes at the end of each row.
      final int index = y * yRowStride + x;
      
      final int yValue = yBytes[index];
      final int uValue = uBytes[uvIndex];
      final int vValue = vBytes[uvIndex];

      int r = (yValue + 1.402 * (vValue - 128)).round();
      int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round();
      int b = (yValue + 1.772 * (uValue - 128)).round();

      yuvImage.setPixelRgba(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255), 255);
    }
  }
  
  // Rotation Angle
  final int rotationAngle = data['rotationAngle'] ?? 0;
  
  // Resize Logic: Maintain Aspect Ratio, Longest Side = 640px
  int targetWidth, targetHeight;
  final double aspectRatio = width / height;

  if (width > height) {
    targetWidth = 640;
    targetHeight = (640 / aspectRatio).round();
  } else {
    targetHeight = 640;
    targetWidth = (640 * aspectRatio).round();
  }

  img.Image resizedImage = img.copyResize(
      yuvImage, 
      width: targetWidth, 
      height: targetHeight, 
      interpolation: img.Interpolation.cubic
  );

  // Rotation
  if (rotationAngle != 0) {
    resizedImage = img.copyRotate(resizedImage, angle: rotationAngle);
  }

  // Encode to JPEG
  return Uint8List.fromList(img.encodeJpg(resizedImage, quality: 85));
}
