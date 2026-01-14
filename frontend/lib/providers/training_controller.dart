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
import 'package:pet_trainer_frontend/services/edge_utils.dart'; // [NEW] Utils & Filters
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
  
  // [NEW] Best Shot (Edge Mode)
  Map<String, dynamic>? _bestFrameData; // Cached Frame Data for generic isolation
  double _bestConf = 0.0;
  
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
  int tSerial = 0; // [NEW]
  int tTransfer = 0; // [NEW]
  bool isGpu = false; // [NEW]

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
  String? bestShotUrl; // [NEW] Best Shot URL
  
  // Debug
  String debugLog = "";
  double maxConfAny = 0.0;
  int maxConfCls = -1;
  Uint8List? debugInputImage;

  // [NEW] Persistence State
  Map<String, dynamic>? lastEdgeResult;
  int missingCount = 0;
  
  // [NEW] Local Timer State
  int _stayStartTime = 0;
  static const int _stayDuration = 2000; // 2 seconds
  
  // [NEW] One Euro Filter State (Class ID -> [x1, y1, x2, y2])
  Map<int, List<OneEuroFilter>>? _boxFilters;
  // Pet Keypoints (17 * 2)
  List<OneEuroFilter>? _keypointFilters;
  // Human Keypoints (17 * 2)
  List<OneEuroFilter>? _humanKeypointFilters;
  
  // [NEW] Unified Smoothing Helper
  void _applySmoothing(List<dynamic> targetBboxList) {
      if (_boxFilters == null) {
          _boxFilters = {};
      }
      
      int now = DateTime.now().millisecondsSinceEpoch;
      
      for(int i=0; i<targetBboxList.length; i++) {
          var box = targetBboxList[i]; 
          // [x1, y1, x2, y2, conf, cls]
          if (box.length > 5) {
              int cls = (box[5] as num).toInt();
              double conf = (box[4] as num).toDouble();
              
              // Only smooth high confidence inputs to avoid dragging ghosts
              // (Threshold matches Edge logic)
              if (conf < 0.25) continue;
              
              // Init filters for this class if missing
              if (!_boxFilters!.containsKey(cls)) {
                  _boxFilters![cls] = [
                     OneEuroFilter(minCutoff: 0.5, beta: 0.007), // x1
                     OneEuroFilter(minCutoff: 0.5, beta: 0.007), // y1
                     OneEuroFilter(minCutoff: 0.5, beta: 0.007), // x2
                     OneEuroFilter(minCutoff: 0.5, beta: 0.007), // y2
                  ];
              }
              
              final filters = _boxFilters![cls]!;
              
              double fx1 = filters[0].filter((box[0] as num).toDouble(), now);
              double fy1 = filters[1].filter((box[1] as num).toDouble(), now);
              double fx2 = filters[2].filter((box[2] as num).toDouble(), now);
              double fy2 = filters[3].filter((box[3] as num).toDouble(), now);
              
              // Update In-Place
              box[0] = fx1;
              box[1] = fy1;
              box[2] = fx2;
              box[3] = fy2;
          }
      }
  }

  // [NEW] Keypoint Smoothing Helper (Pet)
  void _smoothKeypoints(List<dynamic> rawFlatKeypoints) {
      // Expecting [x, y, conf, x, y, conf, ...] for 17 keypoints
      int numPoints = 17;
      if (rawFlatKeypoints.length < numPoints * 3) return;

      // Lazy Init
      if (_keypointFilters == null) {
          _keypointFilters = [];
          for(int i=0; i<numPoints * 2; i++) { // 2 filters per point (x, y)
             _keypointFilters!.add(OneEuroFilter(minCutoff: 0.5, beta: 0.007));
          }
      }

      int now = DateTime.now().millisecondsSinceEpoch;
      
      for (int i = 0; i < numPoints; i++) {
          int baseIdx = i * 3;
          int filterIdx = i * 2;
          
          double rawX = (rawFlatKeypoints[baseIdx] as num).toDouble();
          double rawY = (rawFlatKeypoints[baseIdx + 1] as num).toDouble();
          
          double smoothX = _keypointFilters![filterIdx].filter(rawX, now);
          double smoothY = _keypointFilters![filterIdx+1].filter(rawY, now);
          
          rawFlatKeypoints[baseIdx] = smoothX;
          rawFlatKeypoints[baseIdx + 1] = smoothY;
      }
  }
  
  // [NEW] Keypoint Smoothing Helper (Human)
  void _smoothHumanKeypoints(List<dynamic> rawFlatKeypoints) {
      int numPoints = 17;
      if (rawFlatKeypoints.length < numPoints * 3) return;

      if (_humanKeypointFilters == null) {
          _humanKeypointFilters = [];
          for(int i=0; i<numPoints * 2; i++) { 
             _humanKeypointFilters!.add(OneEuroFilter(minCutoff: 0.5, beta: 0.007));
          }
      }

      int now = DateTime.now().millisecondsSinceEpoch;
      
      for (int i = 0; i < numPoints; i++) {
          int baseIdx = i * 3;
          int filterIdx = i * 2;
          
          double rawX = (rawFlatKeypoints[baseIdx] as num).toDouble();
          double rawY = (rawFlatKeypoints[baseIdx + 1] as num).toDouble();

          double smoothX = _humanKeypointFilters![filterIdx].filter(rawX, now);
          double smoothY = _humanKeypointFilters![filterIdx+1].filter(rawY, now);
          
          rawFlatKeypoints[baseIdx] = smoothX;
          rawFlatKeypoints[baseIdx + 1] = smoothY;
      }
  }
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
  
  // [NEW] Visual Interpolation State (60FPS)
  Timer? _uiTimer;
  List<dynamic> _targetBbox = [];
  List<dynamic> _targetPetKeypoints = [];
  
  // --- Control Methods ---

  Future<void> startTraining(String petType, String difficulty, String mode) async {
    isAnalyzing = true;
    trainingState = TrainingStatus.detecting;
    _currentMode = mode;
    feedback = "트레이닝 시작...";
    debugLog = "";
    bbox = [];
    _targetBbox = []; // Reset Target
    petKeypoints = [];
    _targetPetKeypoints = []; // Reset Target
    humanKeypoints = [];
    _canSendFrame = true;
    _currentFrameId = 0;
    
    // [NEW] Start UI Animation Loop
    _startUiLoop(); 
    
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
    
    // [NEW] Stop UI Loop
    _uiTimer?.cancel();
    _uiTimer = null;
    bestShotUrl = null; // Reset
    
    notifyListeners();
  }
  
  // [NEW] UI Animation Loop (60FPS)
  void _startUiLoop() {
      _uiTimer?.cancel();
      // 16ms ~= 60fps
      _uiTimer = Timer.periodic(Duration(milliseconds: 16), (timer) {
          _uiTick();
      });
  }
  
  void _uiTick() {
      if (!isAnalyzing) return;
      
      bool needsUpdate = false;
      
      // [NEW] Adaptive Alpha Calculation
      // Target: Smooth movement over the specific inference duration
      // If inference takes 200ms, and UI tick is 16ms, we want to move ~1/12th per tick.
      // alpha = dt / latency
      
      // Safety: Min Latency 50ms (avoid div by zero or super fast jitter)
      int safeLatency = (inferenceMs > 50) ? inferenceMs : 50;
      double alpha = (16.0 / safeLatency).clamp(0.01, 0.25); 
      
      // 1. Interpolate BBox
      if (bbox.length == _targetBbox.length) {
          for(int i=0; i<bbox.length; i++) {
              var cur = bbox[i];
              var tgt = _targetBbox[i];
              
              if (cur.length > 5 && tgt.length > 5 && cur[5] == tgt[5]) {
                  // Same object -> Lerp
                  
                  cur[0] += (tgt[0] - cur[0]) * alpha;
                  cur[1] += (tgt[1] - cur[1]) * alpha;
                  cur[2] += (tgt[2] - cur[2]) * alpha;
                  cur[3] += (tgt[3] - cur[3]) * alpha;
                  cur[4] = tgt[4]; 
                  
                  needsUpdate = true;
              } else {
                  // Mismatch -> Snap
                  bbox[i] = List.from(tgt);
                  needsUpdate = true;
              }
          }
      } else {
           bbox = List.from(_targetBbox.map((e) => List.from(e)));
           needsUpdate = true;
      }
      
      // 2. Interpolate Keypoints
      if (petKeypoints.length == _targetPetKeypoints.length) {
           for(int i=0; i<petKeypoints.length; i++) {
               var cur = petKeypoints[i]; 
               var tgt = _targetPetKeypoints[i];
               
               if (cur.length >= 2 && tgt.length >= 2) {
                   cur[0] += (tgt[0] - cur[0]) * alpha;
                   cur[1] += (tgt[1] - cur[1]) * alpha;
                   if (cur.length > 2 && tgt.length > 2) cur[2] = tgt[2];
                   needsUpdate = true;
               }
           }
      } else {
           petKeypoints = List.from(_targetPetKeypoints.map((e) => List.from(e)));
           needsUpdate = true;
      }
      
      if (needsUpdate) {
          notifyListeners();
      }
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

    // Flow Control Check_frameInterval
    // [Optimization] If Edge AI is used, disable artificial throttling (_frameInterval) 
    // to achieve Max FPS limited only by inference time (_isProcessingFrame lock).
    final bool isThrottled = !GlobalSettings.useEdgeAI && 
                             (now - _lastFrameSentTimestamp <= _frameInterval);

    if (!isAnalyzing || 
        isThrottled || 
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
                   // addLog("GPU FATAL: $e"); 
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
                   // addLog("Frame $thisFrameId: Calling AI..."); 
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
                   tSerial = debugInfo['t_serial'] ?? 0; // [NEW]
                   tTransfer = debugInfo['t_transfer'] ?? 0; // [NEW]
                   isGpu = debugInfo['use_gpu'] ?? false; // [NEW]
                }
                
                // [NEW] Best Shot Selection (Edge Mode)
                if (trainingState == TrainingStatus.stay) {
                    double currentConf = (edgeResult['conf_score'] as num?)?.toDouble() ?? 0.0;
                    // Fallback if conf_score is missing: use max bbox conf
                    if (currentConf == 0.0 && edgeResult['bbox'] != null) {
                         for (var box in edgeResult['bbox']) {
                             if (box.length > 4) {
                                 double boxConf = (box[4] as num).toDouble();
                                 if (boxConf > currentConf) currentConf = boxConf;
                             }
                         }
                    }

                    if (_bestFrameData == null || currentConf > _bestConf) {
                        _bestConf = currentConf;
                        // Deep Copy to persist past frame recycling
                        _bestFrameData = {
                            'width': image.width,
                            'height': image.height,
                            'planes': image.planes.map((p) => {
                                'bytes': Uint8List.fromList(p.bytes),
                                'bytesPerRow': p.bytesPerRow,
                                'bytesPerPixel': p.bytesPerPixel
                            }).toList(),
                            'rotationAngle': rotationAngle,
                            'frameId': thisFrameId
                        };
                        print("[TrainingController] Best Shot Cached: $_bestConf");
                    }
                }
                
                // [NEW] Anti-Flickering (Persistence) Logic
                // If detection failed (no bbox), check if we can reuse last result
                bool isValidDetection = false;
                if (edgeResult['bbox'] != null && (edgeResult['bbox'] as List).isNotEmpty) {
                   isValidDetection = true;
                   // --- One Euro Filter (UX Smoothing) ---

                }
                
                if (isValidDetection) {
                    // [Smoothing] Apply One Euro Filter to All Boxes (Pet, Human, Props)
                    if (edgeResult['bbox'] != null) {
                         _applySmoothing(edgeResult['bbox']);
                    }
                    
                    // [Smoothing] Pet Keypoints
                    if (edgeResult['pet_keypoints'] != null && (edgeResult['pet_keypoints'] as List).isNotEmpty) {
                        var rawPets = edgeResult['pet_keypoints'] as List; 
                        if (rawPets.isNotEmpty && rawPets[0] is List) {
                             _smoothKeypoints(rawPets[0]);
                        }
                    }
                    
                    // [Smoothing] Human Keypoints
                    if (edgeResult['human_keypoints'] != null && (edgeResult['human_keypoints'] as List).isNotEmpty) {
                        var rawHumans = edgeResult['human_keypoints'] as List; 
                        if (rawHumans.isNotEmpty && rawHumans[0] is List) {
                             _smoothHumanKeypoints(rawHumans[0]);
                        }
                    }

                    // Success -> Save State
                    lastEdgeResult = Map<String, dynamic>.from(edgeResult);
                    missingCount = 0;
                } else {
                    // Failure -> Attempt Recovery
                    // [UX Fix] Increased buffer from 5 to 20 because FPS is now higher (Optimized)
                    // 20 frames @ 20fps ~= 1.0 sec persistence
                    if (lastEdgeResult != null && missingCount < 20) {
                        // RECOVER: Use last successful result
                        // Note: BBox in lastEdgeResult is ALREADY filtered from previous frame.
                        edgeResult['bbox'] = lastEdgeResult!['bbox'];
                        edgeResult['pet_keypoints'] = lastEdgeResult!['pet_keypoints'];
                        edgeResult['human_keypoints'] = lastEdgeResult!['human_keypoints'];
                        edgeResult['conf_score'] = lastEdgeResult!['conf_score']; // Restore score too
                        
                        missingCount++;
                    } else {
                        // Too many misses -> Clear State & Reset Filters
                        lastEdgeResult = null;
                        missingCount = 0;
                        
                        // [Reset] Filters to prevent jump on next detection
                        if (_boxFilters != null) {
                             for(var list in _boxFilters!.values) {
                                for(var f in list) f.reset();
                             }
                        }
                    }
                }
                
                // [DEBUG] Log only on key frames to avoid spam
                if (thisFrameId % 5 == 0 || thisFrameId == 1) {
                   final shapeStr = edgeResult['debug_info'] != null ? edgeResult['debug_info']['shape'] : "N/A";
                   final errStr = edgeResult['error'] ?? "No Error";
                   // addLog("Frame $thisFrameId: Success:${edgeResult['success']} Shape:$shapeStr Err:$errStr Latency:${latency}ms"); 
                }
                
                // [DEBUG] Check for Edge Errors IMMEDIATELY
                if (edgeResult.containsKey('error') && edgeResult['error'] != null) {
                   final err = edgeResult['error'];
                   // [User Request] Show error in Overlay Log
                   // addLog("⚠️ CRITICAL: $err");
                   errorMessage = "Edge Err: $err";
                   notifyListeners(); // Force UI Update
                   return; 
                }
                
                // [FIX] ===== IMMEDIATELY UPDATE TARGET STATE (AI Data) =====
                
                // Update Detection Data (Target)
                if (edgeResult.containsKey('bbox')) {
                    _targetBbox = edgeResult['bbox'] ?? []; // Update Target
                }
                
                if (edgeResult.containsKey('pet_keypoints')) {
                    var rawPets = edgeResult['pet_keypoints'];
                    // Edge sends List of List (per pet). Server checks 1 pet.
                    // Flatten the first pet's keypoints to [[x,y,c], [x,y,c]...]
                    if (rawPets is List && rawPets.isNotEmpty && rawPets[0] is List) {
                        var flat = rawPets[0] as List; 
                        List<List<dynamic>> structured = [];
                        int count = flat.length ~/ 3;
                        for(int i=0; i<count; i++) {
                            structured.add([flat[i*3], flat[i*3+1], flat[i*3+2]]);
                        }
                        _targetPetKeypoints = structured; // Update Target
                    } else {
                        _targetPetKeypoints = [];
                    }
                }
                if (edgeResult.containsKey('human_keypoints')) { 
                    // Same logic for human
                     var rawHumans = edgeResult['human_keypoints'];
                     if (rawHumans is List && rawHumans.isNotEmpty && rawHumans[0] is List) {
                        var flat = rawHumans[0] as List;
                        List<List<dynamic>> structured = [];
                        int count = flat.length ~/ 3;
                        for(int i=0; i<count; i++) {
                            structured.add([flat[i*3], flat[i*3+1], flat[i*3+2]]);
                        }
                        humanKeypoints = structured; // Human keypoints need targeting too? For now direct is fine or add target
                     } else {
                        humanKeypoints = [];
                     }
                }
                
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
                // Process game logic locally using TARGET State (Fresh Data)
                final gameResult = EdgeGameLogic.processGameLogic(
                   bbox: _targetBbox, // Use Target (AI) State
                   mode: _currentMode,
                   targetClassId: -1, // [Fix] Support All Pets (Dog, Cat, Bird)
                   difficulty: 'easy', // TODO: Get from user settings
                   imageWidth: imageWidth,
                   imageHeight: imageHeight,
                   petKeypoints: _targetPetKeypoints, // Use Target (AI) State
                );
                
                // Update Status locally
                var status = gameResult['status'] as String;
                feedback = gameResult['feedback'] as String? ?? '';
                
                // [NEW] Local Timer Logic for 'Success' State
                // If Edge logic says 'success' (Distance OK), we must enforce 3 sec wait
                if (status == 'success') {
                    if (_stayStartTime == 0) {
                        _stayStartTime = DateTime.now().millisecondsSinceEpoch;
                    }
                    
                    final elapsed = DateTime.now().millisecondsSinceEpoch - _stayStartTime;
                    
                    if (elapsed < _stayDuration) {
                        // Still Waiting -> Override status to 'stay'
                        status = 'stay';
                        final remaining = (_stayDuration - elapsed) / 1000.0;
                        stayProgress = elapsed / _stayDuration.toDouble();
                        progressText = "${remaining.toStringAsFixed(1)}초 유지 중...";
                    } else {
                        // Timer Done -> Real Success
                        status = 'success';
                        stayProgress = 1.0;
                        progressText = "완료!";
                        _stayStartTime = 0; // Reset
                    }
                } else {
                   // Distance Bad or No Pet -> Reset Timer
                   _stayStartTime = 0;
                   stayProgress = 0.0;
                   progressText = "";
                }
                
                trainingState = _parseStatus(status);
                
                // [FIX] Unlock frame lock IMMEDIATELY
                _canSendFrame = true;
                
                // [Optimization] No need to notifyListeners() here.
                // The UI Loop (60FPS) will pick up the state changes automatically.
                
                // [OPTIONAL] Send to server ONLY for SUCCESS 
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
                       'human_keypoints': humanKeypoints,
                       'conf_score': confScore
                   };
                   
                   // [NEW] Attach Best Shot Logic
                   if (_bestFrameData != null) {
                       try {
                           // Convert YUV to JPEG (background isolate)
                           final Uint8List jpegWithId = await compute(resizeAndCompressImage, _bestFrameData!);
                           
                           // Strip last 4 bytes (Frame ID) for clean JPEG
                           final Uint8List cleanJpeg = jpegWithId.sublist(0, jpegWithId.length - 4);
                           
                           successPacket['best_shot_base64'] = base64Encode(cleanJpeg);
                           successPacket['best_conf'] = _bestConf; // Inform server
                           print("[Edge] Sent Best Shot Base64 (${cleanJpeg.length} bytes)");
                           
                           // Reset Cache
                           _bestFrameData = null;
                           _bestConf = 0.0;
                           
                       } catch (e) {
                           print("[Edge] Best Shot Encode Error: $e");
                       }
                   }

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
       // Handle both types if needed, usually string
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
           // [Fix] 성공 메시지라면 프레임 ID가 달라도 무시하지 않고 처리
           if (jsonMap['status'] == 'success') {
              print("Processing Stale Frame for Success: Resp($responseFrameId) != Pending($_pendingFrameId)");
              // 계속 진행 (return 안함)
           } else {
              // Stale frame response
              print("Ignored Stale Frame: Resp($responseFrameId) != Pending($_pendingFrameId)");
              return; 
           }
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
                  final remaining = double.tryParse(match.group(1) ?? '2.0') ?? 2.0;
                  stayProgress = (2.0 - remaining) / 2.0;
                  progressText = "${remaining.toStringAsFixed(1)}초 유지 중...";
              }
           } else if (trainingState != TrainingStatus.success) {
              stayProgress = 0.0;
              progressText = "";
           }

           if (jsonMap.containsKey('bbox')) {
               _targetBbox = jsonMap['bbox']; // Update Target
           }
           if (jsonMap.containsKey('pet_keypoints')) _targetPetKeypoints = jsonMap['pet_keypoints']; // Update Target
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
          print("Received Success Status! keys: ${jsonMap.keys}");
          if (jsonMap.containsKey('base_reward')) {
             final base = jsonMap['base_reward'];
             final bonus = jsonMap['bonus_points'] ?? 0;
             
             // [Fix] Store reward data BEFORE notifying the view
             lastReward = {
               'base': base, 
               'bonus': bonus,
               'level_up_info': jsonMap['level_up_info'] // [New]
             };

             // [NEW] Parse Best Shot URL
             if (jsonMap.containsKey('best_shot_url')) {
                 bestShotUrl = jsonMap['best_shot_url'];
             }

             _charProvider?.gainReward(base, bonus);  
             
             if (onSuccessCallback != null) {
                print("Calling onSuccessCallback...");
                onSuccessCallback?.call(); 
             } else {
                print("onSuccessCallback is NULL");
             }
             
             print("Calling stopTraining...");
             stopTraining(); 
          } else {
             print("Success received but NO base_reward in map!");
          }
       }
       
       if (jsonMap.containsKey('error')) {
           final err = jsonMap['error'];
           print("Server Error Received: $err");
           errorMessage = "Server Error: $err"; 
           feedback = "Server Error: $err"; 
       }

       // notifyListeners(); // Handled by UI Loop

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
