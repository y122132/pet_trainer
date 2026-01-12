import 'dart:async';
import 'package:camera/camera.dart';

// No-op implementation for Web or platforms without TFLite
class EdgeDetector {
  static final EdgeDetector _instance = EdgeDetector._internal();
  factory EdgeDetector() => _instance;
  EdgeDetector._internal();

  bool get isLoaded => false;

  Future<void> initialize() async {
    print("EdgeDetector: Not supported on this platform (Web).");
  }

  Future<Map<String, dynamic>> processFrame(CameraImage image, String mode, int rotationAngle) async {
    return {};
  }

  void close() {}
}
