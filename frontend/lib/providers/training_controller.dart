import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:pet_trainer_frontend/services/socket_client.dart';
import 'package:pet_trainer_frontend/utils/camera_utils.dart';
import 'package:pet_trainer_frontend/providers/char_provider.dart';

// Training Status Enum
enum TrainingStatus {
  ready,
  detecting,
  stay,
  success,
  unknown
}

class TrainingController extends ChangeNotifier {
  final SocketClient _socketClient = SocketClient();
  
  // State Variables
  bool isAnalyzing = false;
  TrainingStatus trainingState = TrainingStatus.ready;
  String feedback = "";
  double confScore = 0.0;
  
  // For Overlay
  List<dynamic> bbox = [];
  List<dynamic> keypoints = [];
  double imageWidth = 0;
  double imageHeight = 0;
  
  // Debug Stats
  int latency = 0;
  double maxConfAny = 0.0;
  int maxConfCls = -1;
  String? errorMessage;
  
  // Stay Progress
  double stayProgress = 0.0;
  String progressText = "";

  // Flow Control
  bool _canSendFrame = true;
  bool _isProcessingFrame = false;
  int _lastFrameSentTimestamp = 0;
  int _frameStartTime = 0;
  static const int _frameInterval = 150;

  // Connection
  bool get isConnected => _socketClient.isConnected;

  // External Reference (Optional)
  CharProvider? _charProvider;
  VoidCallback? onSuccessCallback;

  void setCharProvider(CharProvider provider) {
    _charProvider = provider;
  }

  void startTraining(String petType, String difficulty, String mode) {
    if (isAnalyzing) return;
    
    isAnalyzing = true;
    _canSendFrame = true;
    errorMessage = null;
    notifyListeners();

    _socketClient.connect(petType, difficulty, mode);
    _socketClient.stream.listen(_handleMessage, 
      onError: (e) {
        print("Socket Error: $e");
        errorMessage = "Connection Error: $e";
        _canSendFrame = true; // Recover lock
        notifyListeners();
      },
      onDone: () {
        if (isAnalyzing) {
           errorMessage = "Disconnected from server";
           notifyListeners();
        }
      }
    );
  }

  void stopTraining() {
    isAnalyzing = false;
    _socketClient.disconnect();
    
    // Reset State
    bbox = [];
    keypoints = [];
    feedback = "";
    trainingState = TrainingStatus.ready;
    stayProgress = 0.0;
    progressText = "";
    notifyListeners();
  }

  // --- Frame Processing Logic ---

  Future<void> processFrame(CameraImage image, int sensorOrientation, Orientation currentOrientation) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Flow Control Check
    if (!isAnalyzing || 
        now - _lastFrameSentTimestamp <= _frameInterval || 
        _isProcessingFrame || 
        !_canSendFrame) {
      return;
    }

    _isProcessingFrame = true;

    try {
      // Rotation Logic
      int deviceAngle = (currentOrientation == Orientation.landscape) ? 90 : 0;
      int rotationAngle = (sensorOrientation - deviceAngle + 360) % 360;

      final rawData = {
        'width': image.width,
        'height': image.height,
        'rotationAngle': rotationAngle,
        'planes': image.planes.map((plane) => {
          'bytes': plane.bytes,
          'bytesPerRow': plane.bytesPerRow,
          'bytesPerPixel': plane.bytesPerPixel,
        }).toList(),
      };

      // Compute in Isolate
      final jpegBytes = await compute(processCameraImageToJpeg, rawData);

      if (isAnalyzing && _canSendFrame) {
         _frameStartTime = DateTime.now().millisecondsSinceEpoch;
         _lastFrameSentTimestamp = _frameStartTime;
         _canSendFrame = false; // Lock
         
         _socketClient.sendMessage(jpegBytes);
      }
    } catch (e) {
      print("Frame Process Error: $e");
      _canSendFrame = true; // Recover Lock
    } finally {
      _isProcessingFrame = false;
    }
  }

  // --- Message Handling ---

  void _handleMessage(dynamic message) {
     _canSendFrame = true; // Unlock

     // Calculate Latency
     final now = DateTime.now().millisecondsSinceEpoch;
     if (_frameStartTime > 0) {
       latency = now - _frameStartTime;
     }

     try {
       final data = jsonDecode(message);
       final statusStr = data['status'] as String?;
       
       // Update Training Status
       if (statusStr != null && statusStr != 'keep') {
          trainingState = _parseStatus(statusStr);
       }
       
       // Logic for 'STAY' progress
       if (trainingState == TrainingStatus.stay) {
          final msg = data['message'] as String? ?? '';
          final match = RegExp(r'(\d+\.\d+)').firstMatch(msg);
          if (match != null) {
              final remaining = double.tryParse(match.group(1) ?? '3.0') ?? 3.0;
              stayProgress = (3.0 - remaining) / 3.0;
              progressText = "${remaining.toStringAsFixed(1)}초 유지 중...";
          }
       } else if (trainingState != TrainingStatus.success) {
          stayProgress = 0.0;
          progressText = "";
       }

       // Update Overlay Data
       if (data.containsKey('bbox')) bbox = data['bbox'];
       if (data.containsKey('keypoints')) keypoints = data['keypoints'];
       if (data.containsKey('image_width')) imageWidth = (data['image_width'] as num).toDouble();
       if (data.containsKey('image_height')) imageHeight = (data['image_height'] as num).toDouble();
       
       // Update Feedback
       if (data.containsKey('feedback')) feedback = data['feedback'];
       if (data.containsKey('conf_score')) confScore = (data['conf_score'] as num?)?.toDouble() ?? 0.0;
       
       // Debug Data
       if (data.containsKey('debug_max_conf')) maxConfAny = (data['debug_max_conf'] as num).toDouble();
       if (data.containsKey('debug_max_cls')) maxConfCls = (data['debug_max_cls'] as num).toInt();

       // Handle LLM/System Messages
       if (data.containsKey('char_message')) {
          _charProvider?.updateStatusMessage(data['char_message']);
       }
       if (data.containsKey('message')) { // Legacy or System
          _charProvider?.updateStatusMessage(data['message']);
       }

       // Success Handling
       if (statusStr == 'success') {
          if (data.containsKey('base_reward') && onSuccessCallback != null) {
             final base = data['base_reward'];
             final bonus = data['bonus_points'] ?? 0;
             onSuccessCallback?.call(); // Notify View
             
             // Update Provider Reward
             _charProvider?.gainReward(base, bonus); 
             
             stopTraining(); // Stop Loop
             
             // Pass reward data to callback indirectly or store in state?
             // Actually, View might need the reward data.
             // We can fire a separate event or just let the View read it from Controller?
             // For simplicity, I will store 'lastReward' in Controller or pass it via callback.
             // I'll update callback signature to accept reward.
             // But Dart's VoidCallback doesn't take args. 
             // I will set a `lastReward` property.
             lastReward = {'base': base, 'bonus': bonus};
          }
       }
       
       notifyListeners();

     } catch (e) {
       print("JSON Parse Error: $e");
     }
  }
  
  Map<String, dynamic>? lastReward;

  TrainingStatus _parseStatus(String s) {
    switch (s.toLowerCase()) {
      case 'ready': return TrainingStatus.ready;
      case 'detecting': return TrainingStatus.detecting;
      case 'stay': return TrainingStatus.stay;
      case 'success': return TrainingStatus.success;
      default: return TrainingStatus.unknown;
    }
  }

  @override
  void dispose() {
    _socketClient.disconnect();
    super.dispose();
  }
}
