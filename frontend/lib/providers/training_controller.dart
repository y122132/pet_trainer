import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:pet_trainer_frontend/services/socket_client.dart';
import 'package:pet_trainer_frontend/utils/camera_utils.dart';
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
  
  // State Variables
  bool isAnalyzing = false;
  TrainingStatus trainingState = TrainingStatus.ready;
  // [DEBUG] On-Screen Logging
  String debugLog = "";
  void addLog(String msg) {
     print(msg);
     debugLog += "$msg\n";
     if (debugLog.split('\n').length > 100) { // Keep last 100 lines
        debugLog = debugLog.split('\n').sublist(debugLog.split('\n').length - 100).join('\n');
     }
     notifyListeners();
  }
  String feedback = "";
  double confScore = 0.0;
  int inferenceMs = 0; // [NEW] Latency tracking
  
  // [NEW] Debug: Model input image for visualization
  Uint8List? debugInputImage;
  
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
  
  // [Edge AI]
  String _currentMode = 'playing';


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

  Future<void> startTraining(String petType, String difficulty, String mode) async {
    if (isAnalyzing) return;
    
    _currentMode = mode; // [Edge AI] Store mode
    isAnalyzing = true;

    _canSendFrame = true;
    errorMessage = null;
    _currentFrameId = 0; // Reset ID
    notifyListeners();

    // [Edge AI] Initialize Detector if enabled
    if (GlobalSettings.useEdgeAI) {
      addLog("⭕ [V3-FINAL] StartTraining: Edge AI is ENABLED. Initializing...");
      try {
        await EdgeDetector().initV3();
        addLog("⭕ [V3-FINAL] EdgeDetector init SUCCESS");
      } catch (e) {
        addLog("❌ [V3-FINAL] EdgeDetector init failed: $e");
        errorMessage = "AI Init Failed: $e";
        isAnalyzing = false; // [Fix] Reset state
        notifyListeners();
        return;
      }
    } else {
      addLog("⭕ [V3-FINAL] StartTraining: Edge AI is DISABLED (Server Mode).");
    }

    await _socketClient.connect(petType, difficulty, mode);

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

       if (isAnalyzing && _canSendFrame) {
         // [DEBUG] Trace Frame Start
         // print("Frame Start: $thisFrameId");
         
         _frameStartTime = DateTime.now().millisecondsSinceEpoch;
         _lastFrameSentTimestamp = _frameStartTime;
         _canSendFrame = false; // Lock
         _pendingFrameId = thisFrameId; 
         
         // [Edge AI] Branching
         if (GlobalSettings.useEdgeAI) {
            // [Fix] Lazy Init / Re-init Check
            if (!EdgeDetector().isLoaded) {
                // Try to init on the fly (might cause lag for 1 frame but better than failure)
                print("EdgeAI enabled but not loaded. Initializing...");
                try {
                   await EdgeDetector().initV3();
                } catch (e) {
                   // [V3] Version Tag to confirm fresh build
                   print("[V3-FINAL] Edge Init Failed: $e");
                   errorMessage = "[V3] Init Err: $e";
                   feedback = "AI Init Failed: $e";
                   notifyListeners(); // Update UI
                   return; // Stop processing
                }
            }
            
            if (EdgeDetector().isLoaded) {
                // 1. Edge Inference
                // Log every 5 frames (~1 sec) to confirm liveness
                if (thisFrameId % 5 == 0 || thisFrameId == 1) {
                   addLog("Frame $thisFrameId: Calling AI..."); 
                }
                
                final edgeResult = await EdgeDetector().processFrame(image, _currentMode, rotationAngle);
                
                // [FIX] Update Latency for EVERY frame (not just frame 1 or multiples of 5)
                if (edgeResult.containsKey('debug_info') && edgeResult['debug_info'] != null) {
                   final debugInfo = edgeResult['debug_info'];
                   if (debugInfo.containsKey('inference_ms')) {
                      latency = debugInfo['inference_ms'];
                      inferenceMs = latency; // Keep both in sync
                   }
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
                   // Don't send to server if critical error, just return to visual feedback
                   if (edgeResult.containsKey('stack')) {
                       print(edgeResult['stack']);
                   }
                   return; 
                }
                
                // [FIX] ===== IMMEDIATELY UPDATE UI WITH EDGE RESULTS =====
                // Don't wait for server response! Edge AI is LOCAL.
                
                // Update Detection Data
                if (edgeResult.containsKey('bbox')) bbox = edgeResult['bbox'];
                if (edgeResult.containsKey('pet_keypoints')) petKeypoints = edgeResult['pet_keypoints'];
                if (edgeResult.containsKey('human_keypoints')) humanKeypoints = edgeResult['human_keypoints'];
                
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
                
                // [DEBUG] Log Edge Results to SCREEN
                if (thisFrameId % 5 == 0 || thisFrameId == 1) {
                   final bboxLen = (edgeResult['bbox'] as List?)?.length ?? 0;
                   final debugInfo = edgeResult['debug_info'] as Map?;
                   
                   addLog("[EDGE] Frame $thisFrameId:");
                   addLog("  BBox: $bboxLen detected");
                   addLog("  Success: ${edgeResult['success']}");
                   addLog("  Conf: ${(confScore * 100).toStringAsFixed(1)}%");
                   addLog("  Latency: ${latency}ms");
                   
                   // [CRITICAL] Display Isolate debug info
                   if (debugInfo != null) {
                      addLog("[ISO-DEBUG]:");
                      
                      // Model info
                      addLog("  Input Type: ${debugInfo['input_type']}");
                      addLog("  Output Type: ${debugInfo['output_type']}");
                      addLog("  Input Quant: ${debugInfo['input_quant']}");
                      addLog("  Output Quant: ${debugInfo['output_quant']}");
                      
                      // Input validation
                      addLog("  Input Min: ${debugInfo['input_min']}");
                      addLog("  Input Max: ${debugInfo['input_max']}");
                      final inSample = debugInfo['input_sample'] as String?;
                      if (inSample != null && inSample.length > 40) {
                         addLog("  Input Sample: ${inSample.substring(0, 40)}...");
                      } else {
                         addLog("  Input Sample: ${inSample ?? 'N/A'}");
                      }
                      
                      // Output info
                      addLog("  Output Shape: ${debugInfo['output_shape']}");
                      addLog("  Total Vals: ${debugInfo['output_total']}");
                      addLog("  Output Min: ${debugInfo['output_min']}");
                      addLog("  Output Max: ${debugInfo['output_max']}");
                      addLog("  NonZero Count: ${debugInfo['output_nonzero']}");
                      addLog("  Parse Mode: ${debugInfo['parsing_mode']}");
                      addLog("  Detections: ${debugInfo['detections_found'] ?? 'N/A'}");
                      addLog("  Parse Time: ${debugInfo['parsing_time_ms']}ms");
                      
                      // Sample output values (first few)
                      final outSample = debugInfo['output_sample'] as String?;
                      if (outSample != null && outSample.length > 50) {
                         addLog("  Output Sample: ${outSample.substring(0, 50)}...");
                      } else {
                         addLog("  Output Sample: ${outSample ?? 'N/A'}");
                      }
                   }
                }
                
                // [NEW] ===== LOCAL GAME LOGIC for Edge AI =====
                // Process game logic locally (distance check, status determination)
                final gameResult = EdgeGameLogic.processGameLogic(
                   bbox: edgeResult['bbox'] ?? [],
                   mode: _currentMode,
                   targetClassId: 16, // TODO: Get from user settings (Dog for now)
                   difficulty: 'easy', // TODO: Get from user settings
                   imageWidth: imageWidth,
                   imageHeight: imageHeight,
                   petKeypoints: edgeResult['pet_keypoints'],
                );
                
                // Update Status locally
                final status = gameResult['status'] as String;
                trainingState = _parseStatus(status);
                feedback = gameResult['feedback'] as String? ?? '';
                
                // [FIX] Unlock frame lock IMMEDIATELY (don't wait for server)
                _canSendFrame = true;
                
                // [FIX] Update UI IMMEDIATELY
                notifyListeners();
                
                // [OPTIONAL] Send to server ONLY for SUCCESS (Reward/LLM processing)
                // Server will handle: rewards, character messages, statistics
                if (status == 'success') {
                   edgeResult['frame_id'] = thisFrameId;
                   edgeResult['width'] = logicW;
                   edgeResult['height'] = logicH;
                   edgeResult['status'] = 'success'; // Mark as success
                   edgeResult['mode'] = _currentMode;
                   edgeResult['difficulty'] = 'easy';
    
                   _socketClient.sendMessage(jsonEncode(edgeResult));
                } else {
                   // For non-success frames, optionally send detection data for monitoring
                   // Or skip entirely to reduce server load
                   // (Currently skipping to minimize traffic)
                }
            } else {
                 print("EdgeAI Init Failed completely.");
            }
            
         } else {
            // 2. Server Inference (Legacy)
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
            inferenceMs = latency; // [Fix] Update UI Latency from Server RTT
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
              // [DEBUG] Check for Edge Errors
        if (data.containsKey('error')) {
           final err = data['error'];
           print("Edge Error Received: $err");
           errorMessage = "AI Error: $err"; // Show on screen
           feedback = "AI Error: $err"; // Force feedback update
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
    
    // [Optimization] Keep Edge AI Isolate alive!
    // Repeatedly creating/destroying TFLite isolates causes native instability (Hangs).
    // By keeping it alive, we ensure stability and instant re-entry performance.
    // if (GlobalSettings.useEdgeAI) {
    //   EdgeDetector().close();
    // }
    
    super.dispose();
  }
}
