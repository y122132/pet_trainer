import 'dart:typed_data';
import 'package:image/image.dart' as img;

// --- Top-level function for compute() ---
// Must be top-level or static.
Uint8List resizeAndCompressImage(Map<String, dynamic> data) {
  final int width = data['width'];
  final int height = data['height'];
  final List<dynamic> planes = data['planes'];
  
  // YUV Extraction
  final Uint8List yBytes = planes[0]['bytes'];
  final Uint8List uBytes = planes[1]['bytes'];
  final Uint8List vBytes = planes[2]['bytes'];
  
  int yRowStride = planes[0]['bytesPerRow'];
  if (yBytes.length > width * height && yRowStride <= width) {
    yRowStride = (yBytes.length / height).round();
  }

  int uvRowStride = planes[1]['bytesPerRow'];
  final int uvPixelStride = planes[1]['bytesPerPixel'] ?? 1;
  
  // Calculate Target Size (Max 640px)
  int targetW, targetH;
  final double aspectRatio = width / height;

  if (width > height) {
    targetW = 1280;
    targetH = (1280 / aspectRatio).round();
  } else {
    targetH = 1280;
    targetW = (1280 * aspectRatio).round();
  }
  
  // Create Resized Image Buffer directly
  final img.Image resizedImage = img.Image(width: targetW, height: targetH);

  // Optimized Loop: Iterate over TARGET pixels and sample from SOURCE
  for (int y = 0; y < targetH; y++) {
    for (int x = 0; x < targetW; x++) {
      // Map target coordinate to source coordinate
      int srcX = (x * width / targetW).floor();
      int srcY = (y * height / targetH).floor();
      
      // Calculate indices in source buffers
      final int uvIndex = uvPixelStride * (srcX / 2).floor() + uvRowStride * (srcY / 2).floor();
      final int index = srcY * yRowStride + srcX;
      
      // Safety Check
      if (index >= yBytes.length || uvIndex >= uBytes.length || uvIndex >= vBytes.length) continue;

      final int yValue = yBytes[index];
      final int uValue = uBytes[uvIndex];
      final int vValue = vBytes[uvIndex];

      int r = (yValue + 1.402 * (vValue - 128)).round();
      int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round();
      int b = (yValue + 1.772 * (uValue - 128)).round();

      resizedImage.setPixelRgba(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255), 255);
    }
  }
  
  // Rotation Angle
  final int rotationAngle = data['rotationAngle'] ?? 0;
  img.Image finalImage = resizedImage;

  // Rotation
  if (rotationAngle != 0) {
    finalImage = img.copyRotate(finalImage, angle: rotationAngle);
  }

  // Encode to JPEG (Quality 80)
  List<int> jpeg = img.encodeJpg(finalImage, quality: 80);

  // [NEW] Append Frame ID (4 bytes, Big Endian)
  int frameId = data['frameId'] ?? -1;
  if (frameId != -1) {
    // 32-bit integer to 4 bytes
    final idBytes = Uint8List(4)
      ..buffer.asByteData().setInt32(0, frameId, Endian.big);
    jpeg = [...jpeg, ...idBytes];
  }

  return Uint8List.fromList(jpeg);
}
