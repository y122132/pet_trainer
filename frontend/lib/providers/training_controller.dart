import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:pet_trainer_frontend/services/socket_client.dart';
import 'package:pet_trainer_frontend/utils/camera_utils.dart';
import 'package:pet_trainer_frontend/providers/char_provider.dart';
import 'package:pet_trainer_frontend/services/edge_detector.dart'; // [Edge AI]
import 'package:pet_trainer_frontend/services/edge_game_logic.dart'; // [Edge AI Game Logic]
import 'package:pet_trainer_frontend/config/global_settings.dart'; // [Edge AI]


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
  CharProvider? _charProvider;
  
  // --- State Variables ---
  bool isAnalyzing = false;
  TrainingStatus trainingState = TrainingStatus.ready;
  String _currentMode = "playing"; // Default
  
  // Stats
  double confScore = 0.0;
  String feedback = "";
  String errorMessage = "";
  
  // Latency & Profiling
  int inferenceMs = 0; 
  int latency = 0;
  // [NEW] Granular Profiling Stats
  int tPreprocess = 0;
  int tInference = 0;
  int tFlatten = 0;
  int tNms = 0;

  // Detection Data
  List<dynamic> bbox = [];
  List<dynamic> keypoints = []; // Legacy
  List<dynamic> petKeypoints = [];
  List<dynamic> humanKeypoints = [];
  
  // Image Info
  double imageWidth = 1.0;
  double imageHeight = 1.0;
  
  // Game Logic State
  double stayProgress = 0.0;
  String progressText = "";
  Map<String, dynamic>? lastReward;
  VoidCallback? onSuccessCallback;
  
  // Debug
  String debugLog = "";
  double maxConfAny = 0.0;
  int maxConfCls = -1;
  Uint8List? debugInputImage;

  // --- Internal Flags & Flow Control ---
  bool _isProcessingFrame = false;
  bool _canSendFrame = true; // Lock mechanism
  int _frameInterval = 100; // ms
  int _lastFrameSentTimestamp = 0;
  int _frameStartTime = 0;
  
  // Sync
  int _currentFrameId = 0;
  int _pendingFrameId = -1;
  StreamSubscription? _socketSubscription;

  TrainingController() {
    _socketSubscription = _socketClient.stream.listen(_handleMessage);
  }

  void setCharProvider(CharProvider provider) {
    _charProvider = provider;
  }
  
  // --- Control Methods ---

  Future<void> startTraining(String petType, String difficulty, String mode) async {
    isAnalyzing = true;
    trainingState = TrainingStatus.detecting;
    _currentMode = mode;
    feedback = "트레이닝 시작...";
    debugLog = "";
    bbox = [];
    petKeypoints = [];
    humanKeypoints = [];
    _canSendFrame = true;
    _currentFrameId = 0;
    
    // Connect Socket if needed (Legacy backup)
    if (!_socketClient.isConnected) {
        await _socketClient.connect(petType, difficulty, mode);
    }
    
    notifyListeners();
  }

  void stopTraining() {
    isAnalyzing = false;
    trainingState = TrainingStatus.ready;
    feedback = "";
    _canSendFrame = true;
    notifyListeners();
  }
  
  // --- Logging ---
  void addLog(String msg) {
     print(msg);
     debugLog += "$msg\n";
     if (debugLog.split('\n').length > 100) { // Keep last 100 lines
        debugLog = debugLog.split('\n').sublist(debugLog.split('\n').length - 100).join('\n');
     }
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

      if (isAnalyzing && _canSendFrame) {
         // [DEBUG] Trace Frame Start
         _frameStartTime = DateTime.now().millisecondsSinceEpoch;
         _lastFrameSentTimestamp = _frameStartTime;
         _canSendFrame = false; // Lock
         _pendingFrameId = thisFrameId; 
         
         // [Edge AI] Branching
         if (GlobalSettings.useEdgeAI) {
            // [Fix] Lazy Init / Re-init Check
            if (!EdgeDetector().isLoaded) {
                // Try to init on the fly 
                print("EdgeAI enabled but not loaded. Initializing...");
                try {
                   await EdgeDetector().initV3();
                } catch (e) {
                   print("[V3-FINAL] Edge Init Failed: $e");
                   errorMessage = "[V3] Init Err: $e";
                   feedback = "AI Init Failed: $e";
                   notifyListeners(); 
                   return; 
                }
            }
            
            if (EdgeDetector().isLoaded) {
                // 1. Edge Inference
                // Log every 5 frames (~1 sec) to confirm liveness
                if (thisFrameId % 5 == 0 || thisFrameId == 1) {
                   addLog("Frame $thisFrameId: Calling AI..."); 
                }
                
                final edgeResult = await EdgeDetector().processFrame(image, _currentMode, rotationAngle);
                
                // [FIX] Update Latency for EVERY frame
                if (edgeResult.containsKey('debug_info') && edgeResult['debug_info'] != null) {
                   final debugInfo = edgeResult['debug_info'];
                   if (debugInfo.containsKey('inference_ms')) {
                      latency = debugInfo['inference_ms'];
                      inferenceMs = latency; 
                   }
                   // [NEW] Populate Granular Stats
                   tPreprocess = debugInfo['t_preprocess'] ?? 0;
                   tInference = debugInfo['t_inference'] ?? 0;
                   tFlatten = debugInfo['t_flatten'] ?? 0;
                   tNms = debugInfo['t_nms'] ?? 0;
                }
                
                // [DEBUG] Log only on key frames to avoid spam
                if (thisFrameId % 5 == 0 || thisFrameId == 1) {
                   final shapeStr = edgeResult['debug_info'] != null ? edgeResult['debug_info']['shape'] : "N/A";
                   final errStr = edgeResult['error'] ?? "No Error";
                   addLog("Frame $thisFrameId: Success:${edgeResult['success']} Shape:$shapeStr Err:$errStr Latency:${latency}ms"); 
                }
                
                // [DEBUG] Check for Edge Errors IMMEDIATELY
                if (edgeResult.containsKey('error')) {
                   final err = edgeResult['error'];
                   print("Edge Error Local Catch: $err");
                   errorMessage = "Edge Error: $err";
                   feedback = "Edge Error: $err";
                   notifyListeners();
                   if (edgeResult.containsKey('stack')) {
                       print(edgeResult['stack']);
                   }
                   return; 
                }
                
                // [FIX] ===== IMMEDIATELY UPDATE UI WITH EDGE RESULTS =====
                
                // Update Detection Data
                if (edgeResult.containsKey('bbox')) bbox = edgeResult['bbox'] ?? [];
                if (edgeResult.containsKey('pet_keypoints')) petKeypoints = edgeResult['pet_keypoints'] ?? [];
                if (edgeResult.containsKey('human_keypoints')) humanKeypoints = edgeResult['human_keypoints'] ?? [];
                
                // Handle Orientation for Image Dimensions
                int logicW = image.width;
                int logicH = image.height;
                if (rotationAngle == 90 || rotationAngle == 270) {
                   logicW = image.height;
                   logicH = image.width;
                }
                imageWidth = logicW.toDouble();
                imageHeight = logicH.toDouble();
                
                // Update Confidence Score
                if (edgeResult.containsKey('conf_score')) {
                   confScore = (edgeResult['conf_score'] as num?)?.toDouble() ?? 0.0;
                }
                
                // [NEW] Update debug input image for visualization
                if (edgeResult.containsKey('debug_info') && edgeResult['debug_info'] != null) {
                   final debugInfo = edgeResult['debug_info'] as Map?;
                   if (debugInfo != null && debugInfo.containsKey('input_image_png')) {
                      debugInputImage = debugInfo['input_image_png'] as Uint8List?;
                   }
                }
                
                // [NEW] ===== LOCAL GAME LOGIC for Edge AI =====
                // Process game logic locally 
                final gameResult = EdgeGameLogic.processGameLogic(
                   bbox: bbox,
                   mode: _currentMode,
                   targetClassId: 16, // TODO: Get from user settings 
                   difficulty: 'easy', // TODO: Get from user settings
                   imageWidth: imageWidth,
                   imageHeight: imageHeight,
                   petKeypoints: petKeypoints,
                );
                
                // Update Status locally
                final status = gameResult['status'] as String;
                trainingState = _parseStatus(status);
                feedback = gameResult['feedback'] as String? ?? '';
                
                // [FIX] Unlock frame lock IMMEDIATELY
                _canSendFrame = true;
                
                // [FIX] Update UI IMMEDIATELY
                notifyListeners();
                
                // [OPTIONAL] Send to server ONLY for SUCCESS 
                if (status == 'success') {
                   // Create a minimal success packet
                   final successPacket = {
                       'frame_id': thisFrameId,
                       'width': logicW,
                       'height': logicH,
                       'status': 'success',
                       'mode': _currentMode,
                       'difficulty': 'easy',
                       'bbox': bbox,
                       'pet_keypoints': petKeypoints,
                       'human_keypoints': humanKeypoints
                   };
                   
                   _socketClient.sendMessage(jsonEncode(successPacket));
                }
            } else {
                 print("EdgeAI Init Failed completely.");
            }
            
         } else {
            // 2. Server Inference (Legacy)
            final rawData = {
                'width': image.width,
                'height': image.height,
                'rotationAngle': rotationAngle,
                'frameId': thisFrameId, 
                'planes': image.planes.map((plane) => {
                  'bytes': plane.bytes,
                  'bytesPerRow': plane.bytesPerRow,
                  'bytesPerPixel': plane.bytesPerPixel,
                }).toList(),
            };
            final jpegBytes = await compute(resizeAndCompressImage, rawData);
            _socketClient.sendMessage(jpegBytes);
         }

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
     
     // [NEW] Parse Check
     try {
       final data = typeof(message) == 'string' ? jsonDecode(message) : message; // Handle both types if needed, usually string
       // But _socketClient likely returns String. 
       
       // Handle binary? No, we expect JSON text usually. 
       // If it's binary, jsonDecode throws.
       final Map<String, dynamic> jsonMap = (message is String) ? jsonDecode(message) : (message is Map ? message : {});
       
       final int responseFrameId = jsonMap['frame_id'] ?? -1;
       
       // Only process logic if ID matches (Strict Sync)
       if (responseFrameId != -1 && responseFrameId == _pendingFrameId) {
          _canSendFrame = true; // Unlock for next frame
          
          final now = DateTime.now().millisecondsSinceEpoch;
          if (_frameStartTime > 0) {
            latency = now - _frameStartTime;
            inferenceMs = latency; 
          }
       } else if (responseFrameId != -1 && responseFrameId != _pendingFrameId) {
          // Stale frame response
          print("Ignored Stale Frame: Resp($responseFrameId) != Pending($_pendingFrameId)");
          return; 
       }
       
       if (!GlobalSettings.useEdgeAI) {
           // Only update state from server if NOT using Edge AI (or if it's a success confirmation)
           
           final statusStr = jsonMap['status'] as String?; 
           if (statusStr != null && statusStr != 'keep') {
              trainingState = _parseStatus(statusStr);
           }
           
           if (trainingState == TrainingStatus.stay) {
              final msg = jsonMap['message'] as String? ?? '';
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

           if (jsonMap.containsKey('bbox')) bbox = jsonMap['bbox'];
           if (jsonMap.containsKey('pet_keypoints')) petKeypoints = jsonMap['pet_keypoints'];
           if (jsonMap.containsKey('human_keypoints')) humanKeypoints = jsonMap['human_keypoints'];
           
           // Fallback
           if (jsonMap.containsKey('keypoints') && humanKeypoints.isEmpty) keypoints = jsonMap['keypoints']; 
           if (jsonMap.containsKey('image_width')) imageWidth = (jsonMap['image_width'] as num).toDouble();
           if (jsonMap.containsKey('image_height')) imageHeight = (jsonMap['image_height'] as num).toDouble();
           
           if (jsonMap.containsKey('feedback')) feedback = jsonMap['feedback'];
           if (jsonMap.containsKey('conf_score')) confScore = (jsonMap['conf_score'] as num?)?.toDouble() ?? 0.0;
           
           // Debug Data
           if (jsonMap.containsKey('debug_max_conf')) maxConfAny = (jsonMap['debug_max_conf'] as num).toDouble();
           if (jsonMap.containsKey('debug_max_cls')) maxConfCls = (jsonMap['debug_max_cls'] as num).toInt();
       }

       // Handle LLM/System Messages (Always allow these)
       if (jsonMap.containsKey('char_message')) {
          _charProvider?.updateStatusMessage(jsonMap['char_message']);
       }
       if (jsonMap.containsKey('message')) { 
          _charProvider?.updateStatusMessage(jsonMap['message']);
       }

       // Success Handling (Server Auth)
       final statusStr = jsonMap['status'] as String?;
       if (statusStr == 'success') {
          if (jsonMap.containsKey('base_reward')) {
             final base = jsonMap['base_reward'];
             final bonus = jsonMap['bonus_points'] ?? 0;
             
             lastReward = {'base': base, 'bonus': bonus};

             _charProvider?.gainReward(base, bonus); 
             
             if (onSuccessCallback != null) {
                onSuccessCallback?.call(); 
             }
             
             stopTraining(); 
          }
       }
       
       if (jsonMap.containsKey('error')) {
           final err = jsonMap['error'];
           print("Server Error Received: $err");
           errorMessage = "Server Error: $err"; 
           feedback = "Server Error: $err"; 
       }

       notifyListeners();

     } catch (e) {
       print("JSON Parse Error: $e");
     }
  }
  
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
    _socketSubscription?.cancel();
    _socketClient.disconnect();
    super.dispose();
  }
  
  // Helper for JSON decode
  dynamic typeof(dynamic obj) => obj.runtimeType.toString();
}
