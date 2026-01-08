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
  List<dynamic> keypoints = []; // Legacy or Mixed
  List<dynamic> petKeypoints = [];
  List<dynamic> humanKeypoints = [];
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
  
  // [NEW] Frame Synchronization
  int _currentFrameId = 0;
  int _pendingFrameId = -1; // ID of the frame currently being processed by server

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
    _currentFrameId = 0; // Reset ID
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
    petKeypoints = [];
    humanKeypoints = [];
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

      // [NEW] Increment Frame ID
      _currentFrameId++;
      final thisFrameId = _currentFrameId;

      final rawData = {
        'width': image.width,
        'height': image.height,
        'rotationAngle': rotationAngle,
        'frameId': thisFrameId, // [NEW] Pass ID to Isolate
        'planes': image.planes.map((plane) => {
          'bytes': plane.bytes,
          'bytesPerRow': plane.bytesPerRow,
          'bytesPerPixel': plane.bytesPerPixel,
        }).toList(),
      };

      // Compute in Isolate (Resize to 640px, JPEG 85)
      final jpegBytes = await compute(resizeAndCompressImage, rawData);

      if (isAnalyzing && _canSendFrame) {
         _frameStartTime = DateTime.now().millisecondsSinceEpoch;
         _lastFrameSentTimestamp = _frameStartTime;
         _canSendFrame = false; // Lock
         _pendingFrameId = thisFrameId; // [NEW] Track pending ID
         
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
     
     // [NEW] Parse Check - Is this the frame response we are waiting for?
     // We do NOT unlock _canSendFrame until we verify ID or detect error/timeout (timeout separate logic)
     // Actually, receiving ANY message usually implies socket is alive.
     
     try {
       final data = jsonDecode(message);
       
       // [NEW] Latency & Lock Logic
       final int responseFrameId = data['frame_id'] ?? -1;
       
       // Only process logic if ID matches (Strict Sync)
       // If ID is -1, it's an async event (Greeting, Idle, etc) -> Process without unlocking frame
       if (responseFrameId != -1 && responseFrameId == _pendingFrameId) {
          _canSendFrame = true; // Unlock for next frame
          
          final now = DateTime.now().millisecondsSinceEpoch;
          if (_frameStartTime > 0) {
            latency = now - _frameStartTime;
          }
       } else if (responseFrameId != -1 && responseFrameId != _pendingFrameId) {
          // Stale frame response (Old) -> DONT unlock, ignore latency
          print("Ignored Stale Frame: Resp($responseFrameId) != Pending($_pendingFrameId)");
          return; 
       }
       // If responseFrameId == -1, it is a system message. Pass through but don't unlock frame (unless we need to?)
       // Actually, async messages shouldn't block frame sending. But strictly, frame lock controls FRAME rate.
       // Async messages don't affect that.
       
       // ... Rest of logic updates state ...
       
       final statusStr = data['status'] as String?; // [Restored] Fix compilation error
       
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
       
       // Handle New Dual Skeleton
       if (data.containsKey('pet_keypoints')) petKeypoints = data['pet_keypoints'];
       if (data.containsKey('human_keypoints')) humanKeypoints = data['human_keypoints'];
       
       // Fallback
       if (data.containsKey('keypoints') && humanKeypoints.isEmpty) keypoints = data['keypoints']; // Legacy
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
          if (data.containsKey('base_reward')) {
             final base = data['base_reward'];
             final bonus = data['bonus_points'] ?? 0;
             
             // [Fix] Store reward data BEFORE notifying the view
             lastReward = {'base': base, 'bonus': bonus};

             // Update Provider Reward (Stats)
             _charProvider?.gainReward(base, bonus); 
             
             // Notify View to show dialog
             if (onSuccessCallback != null) {
                onSuccessCallback?.call(); 
             }
             
             stopTraining(); // Stop Loop
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
