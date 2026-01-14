import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:pet_trainer_frontend/services/edge_utils.dart';
import 'package:image/image.dart' as img;

// --- Commands ---
enum Cmd { init, detect, close, ping }

// --- Global Variables for Isolate ---
int _pngFrameCounter = 0; // For PNG generation throttling

class EdgeDetector {
  static final EdgeDetector _instance = EdgeDetector._internal();
  factory EdgeDetector() => _instance;
  EdgeDetector._internal();

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  Completer<void>? _initCompleter;
  
  // Requests map to match responses
  final Map<int, Completer<Map<String, dynamic>>> _requests = {};
  int _requestIdCounter = 0;
  
  // [NEW] Ping Completer
  Completer<bool>? _pingCompleter;

  bool get isLoaded => _sendPort != null;

  // [Fix] Init Lock to prevent Race Conditions (Double Tap)
  bool _isInitializing = false;

  Future<void> initV3() async {
    print("Probe: Init Start (Main Thread Asset Loading)");
    if (_isInitializing) {
       print("Probe: Already Initializing");
       return _initCompleter?.future ?? Future.value();
    }
    
    if (isLoaded) {
       bool isHealthy = await _checkHealth();
       if (isHealthy) return;
       _kill();
    } else {
       _kill();
    }
    
    _isInitializing = true;

    try {
        final initCompleter = Completer<void>();
        final receivePort = ReceivePort();
        
        _initCompleter = initCompleter; 
        _receivePort = receivePort;
        
        // [Main Thread] Load Assets Here!
        // ServicesBinding is guaranteed availability here.
        print("Probe: Loading Asset Bytes on Main Thread...");
        final petData = await rootBundle.load('assets/models/pet_pose_int8.tflite');
        final objData = await rootBundle.load('assets/models/yolo11n_int8.tflite');
        final humanData = await rootBundle.load('assets/models/yolo11n-pose_int8.tflite');
        
        final petBytes = Uint8List.fromList(petData.buffer.asUint8List(petData.offsetInBytes, petData.lengthInBytes));
        final objBytes = Uint8List.fromList(objData.buffer.asUint8List(objData.offsetInBytes, objData.lengthInBytes));
        final humanBytes = Uint8List.fromList(humanData.buffer.asUint8List(humanData.offsetInBytes, humanData.lengthInBytes));
        print("Probe: Assets Extracted Safely. Pet=${petBytes.length}, Obj=${objBytes.length}, Human=${humanBytes.length}");
        
        print("Probe: Spawning Isolate...");
        final rootToken = RootIsolateToken.instance;
        if (rootToken == null) throw Exception("RootToken Null");
        
        _isolate = await Isolate.spawn(
          _isolateEntry, 
          _IsolateInitData(receivePort.sendPort, rootToken),
        );
        print("Probe: Isolate Spawned");
    
        receivePort.listen((message) {
          // [Listening for LOGS]
          if (message is Map<String, dynamic> && message.containsKey('log')) {
             print("Probe [ISO]: ${message['log']}");
             return;
          }

          if (message is SendPort) {
            _sendPort = message; 
            // [Fix] Send BYTES to Isolate
            _sendPort?.send({
                'cmd': Cmd.init,
                'petBytes': petBytes,
                'objBytes': objBytes,
                'humanBytes': humanBytes
            }); 
            print("Probe: Init Cmd Sent (With Bytes)");
          } 
          // ... (Rest of listener same as before)
          else if (message is Map<String, dynamic>) {
            if (message.containsKey('init_done')) {
               if (message['init_done'] == true) {
                  if (!initCompleter.isCompleted) initCompleter.complete();
               } else {
                  String err = message['error'] ?? "Unknown Init Error";
                  String stack = message['stack'] ?? ""; 
                  if (!initCompleter.isCompleted) initCompleter.completeError("$err\n$stack");
               }
            } else if (message.containsKey('pong')) {
              _pingCompleter?.complete(message['pong'] == true);
            } else if (message.containsKey('req_id')) {
              final id = message['req_id'];
              final reqCompleter = _requests.remove(id);
              reqCompleter?.complete(message);
            }
          }
        });

        await initCompleter.future.timeout(const Duration(seconds: 10), onTimeout: () { // Increased timeout for heavy transfer
           _kill(); 
           throw TimeoutException("Init Timeout");
        });
    
    } catch (e) {
        _kill(); 
        rethrow;
    } finally {
       _isInitializing = false;
    }
  }
  
  // [NEW] Health Check
  Future<bool> _checkHealth() async {
      final pingCompleter = Completer<bool>();
      _pingCompleter = pingCompleter; // Assign to global for listener
      
      _sendPort?.send({'cmd': Cmd.ping});
      
      try {
        // [Fix] Await local variable
        final result = await pingCompleter.future.timeout(const Duration(milliseconds: 200));
        return result; 
      } catch (e) {
        return false;
      }
  }

  void _kill() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _receivePort?.close();
    _receivePort = null;
    
    // [Fix] Cancel all pending requests to prevent deadlocks
    for (var completer in _requests.values) {
       if (!completer.isCompleted) {
          completer.completeError("Isolate Killed");
       }
    }
    _requests.clear();
    
    // [Fix] Cancel pending init
    // Note: Local completers in initialize() handle their own timeout/state,
    // but we clear the global ref to signal "Reset".
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
       _initCompleter!.completeError("Isolate Killed (Reset)");
    }
    _initCompleter = null;
    
    // [Fix] Cancel pending ping
    if (_pingCompleter != null && !_pingCompleter!.isCompleted) {
       _pingCompleter!.complete(false); 
    }
    _pingCompleter = null;
  }

  
  // Manual Close
  void close() {
     _sendPort?.send({'cmd': Cmd.close});
     // Give time for cleanup? No, just kill local ref
     Future.delayed(const Duration(milliseconds: 100), () {
        _kill();
     });
  }

  // [Fix] Frame Skipping Flag
  bool _isProcessing = false;

  Future<Map<String, dynamic>> processFrame(CameraImage image, String mode, int rotationAngle) async {
    if (_sendPort == null) return {};

    // [Optim] Frame Skipping: Drop request if Isolate is busy
    if (_isProcessing) {
       return {};
    }
    _isProcessing = true;
    
    final completer = Completer<Map<String, dynamic>>();
    final id = _requestIdCounter++;
    _requests[id] = completer;

    // [Profiling] Measure Main Thread Serialization Time
    final swSerial = Stopwatch()..start();
    
    // Convert CameraImage to transferable map (bytes)
    // [Optim] Flatten structure to minimize deep copy overhead.
    // Sending raw bytes directly.
    final rawData = {
      'width': image.width,
      'height': image.height,
      'bytes0': image.planes[0].bytes,
      'bytes1': image.planes[1].bytes,
      'bytes2': image.planes[2].bytes,
      'stride0': image.planes[0].bytesPerRow,
      'stride1': image.planes[1].bytesPerRow,
      'uvPixelStride': image.planes[1].bytesPerPixel,
    };
    swSerial.stop();

    _sendPort!.send({
      'cmd': Cmd.detect,
      'req_id': id,
      'sent_ts': DateTime.now().millisecondsSinceEpoch,
      't_serial': swSerial.elapsedMilliseconds,
      'data': rawData, // Simplified Data Packet
      'mode': mode,
      'rotation': rotationAngle
    });

    try {
        return await completer.future.timeout(const Duration(milliseconds: 5000), onTimeout: () {
          _requests.remove(id);
          throw TimeoutException("Edge AI Isolate Hung (5000ms)"); 
        });
    } catch(e) {
        return {'success': false, 'error': e.toString()};
    } finally {
        _isProcessing = false;
    }
  }
  
  // [Fix] Add explicit re-init trigger for hot-restart scenarios
  Future<void> ensureInitialized() async {
     if (!isLoaded) {
        await initV3();
     }
  }
}

class _IsolateInitData {
  final SendPort sendPort;
  final RootIsolateToken rootToken;
  _IsolateInitData(this.sendPort, this.rootToken);
}

// --- Isolate Entry Point ---
// [State] Global GPU Status
bool _gpuEnabled = false;

void _isolateEntry(_IsolateInitData initData) async {
  // Helper for logging to main thread
  void log(String msg) {
     initData.sendPort.send({'log': msg});
  }

  // Initialize Background Channel
  try {
    BackgroundIsolateBinaryMessenger.ensureInitialized(initData.rootToken);
    log("BinaryMessenger Initialized");
  } catch (e) {
    log("BinaryMessenger Fail: $e");
  }
  
  final receivePort = ReceivePort();
  initData.sendPort.send(receivePort.sendPort);

  Interpreter? interpreterPet;
  Interpreter? interpreterObj;
  Interpreter? interpreterHuman;
  
  // [GC Safety & Optim] Keep references to buffers to prevent GC during Isolate life
  final List<Uint8List> _buffers = []; 
  
  // [Smart Init] Store resolved input shapes
  List<int> _petInputShape = [1, 640, 640, 3]; 
  
  // [PERF] Persistent Buffers for Reuse
  // 640*640*3 = 1,228,800 elements
  Float32List? _inputFloatBuffer;
  Uint8List? _inputQuantBuffer; // Scratchpad for quantization if needed
  Float32List? _outputBufferPet;
  Float32List? _outputBufferObj;
  Float32List? _outputBufferHuman;

  // [Phase 3] Persistent 3D Output Containers to avoid GC
  List<List<List<double>>>? _petOutput3D;
  List<List<List<double>>>? _objOutput3D;
  List<List<List<double>>>? _humanOutput3D;
  
  // --- Persistence State ---
  // Key: Class ID (e.g. 32 Ball)
  final Map<int, OneEuroFilter> objFilters = {}; 
  final Map<int, List<dynamic>> lastPropBoxes = {}; // Ghost Tracking
  final Map<int, int> propMissingCounts = {}; // Frames missed
  const int MAX_PROP_MISSING = 5; // ~0.15s (30fps) to 0.5s (10fps). 5 frames is safe.

  receivePort.listen((message) async {
    final cmd = message['cmd'] as Cmd;
    
    if (cmd == Cmd.init) {
      log("Cmd.init [STRICT MODE]");
      try {
        // Initialize buffers from message
        final petBytes = message['petBytes'] as Uint8List;
        final objBytes = message['objBytes'] as Uint8List;
        final humanBytes = message['humanBytes'] as Uint8List;
        
        _buffers.add(petBytes);
        _buffers.add(objBytes);
        _buffers.add(humanBytes);

        // --- Helper: Safe Init with Fallback ---
        Interpreter safeInit(String name, Uint8List bytes, {bool useGpu = false}) {
           InterpreterOptions options = InterpreterOptions();
           // [Optim] Crucial for CPU/NPU performance
           options.threads = 4; 
           
           // [Strategy] Int8 Models + Android = NNAPI (NPU) or XNNPACK (CPU)
           if (useGpu) {
               if (Platform.isAndroid) {
                   // Int8 is best on NNAPI (NPU)
                   options.useNnApiForAndroid = true;
               }
           }
           
           try {
              final interpreter = Interpreter.fromBuffer(bytes, options: options);
              interpreter.resizeInputTensor(0, [1, 640, 640, 3]);
              interpreter.allocateTensors();
              return interpreter;
           } catch (e) {
              if (useGpu) {
                  log("HW Accel Failed for $name. $e. Fallback to CPU.");
                  return safeInit(name, bytes, useGpu: false); // Recursive Fallback
              }
              throw e; 
           }
        }

        // Initialize Interpreters
        bool gpuUsed = false;
        try {
            log("Loading Pet Model (CPU XNNPACK)...");
            // [Optim] Int8 Models run faster on XNNPACK (CPU) than NNAPI/GPU on many devices.
            interpreterPet = safeInit("Pet", petBytes, useGpu: false);
            gpuUsed = false; 
        } catch (e) {
            log("Pet Init Failed: $e");
            // Fail gracefully or rethrow? 
            throw e; 
        }
        
        // [Fix] Initialize Pet Shapes & Buffers (Missing from previous edit)
        _petInputShape = interpreterPet!.getInputTensor(0).shape; // [1, 640, 640, 3]
        var outShape = interpreterPet!.getOutputTensor(0).shape;
        _petOutput3D = List.generate(outShape[0], (_) => List.generate(outShape[1], (_) => List.filled(outShape[2], 0.0)));
        
        log("Pet OK. Input: $_petInputShape Output: $outShape");

        // [Fix] Load Object Model safely using gpuUsed status
        log("Loading Obj Model (CPU)...");
        interpreterObj = safeInit("Obj", objBytes, useGpu: false); 
        outShape = interpreterObj!.getOutputTensor(0).shape;
        _objOutput3D = List.generate(outShape[0], (_) => List.generate(outShape[1], (_) => List.filled(outShape[2], 0.0)));
        log("Obj OK.");

        // [Fix] Load Human Model safely
        log("Loading Human Model (CPU)...");
        interpreterHuman = safeInit("Human", humanBytes, useGpu: false);
        outShape = interpreterHuman!.getOutputTensor(0).shape;
        _humanOutput3D = List.generate(outShape[0], (_) => List.generate(outShape[1], (_) => List.filled(outShape[2], 0.0)));
        log("Human OK.");
        
        // [State] Store Global GPU Status
        _gpuEnabled = gpuUsed;

        log("All Models Ready (Strict Persistent Mode).");
        initData.sendPort.send({'init_done': true});
        
      } catch (e, stack) {
        log("Init Error: $e");
        log("Stack: $stack");
        initData.sendPort.send({'init_done': false, 'error': e.toString(), 'stack': stack.toString()});
      }
    } 
    else if (cmd == Cmd.detect) {
      final sw = Stopwatch()..start(); 
      final id = message['req_id'] as int;
      final rawData = message['data'];
      final mode = message['mode'];
      final rotation = message['rotation'] ?? 0;
      final sentTs = message['sent_ts'] as int? ?? 0;
      final tSerial = message['t_serial'] as int? ?? 0;
      
      final now = DateTime.now().millisecondsSinceEpoch;
      final tTransfer = (sentTs > 0) ? (now - sentTs) : 0;
      
      final result = <String, dynamic>{
        'req_id': id,
        'success': false,
        'bbox': [], 
        'pet_keypoints': [], 
        'human_keypoints': [], 
        'conf_score': 0.0,
        'debug_info': <String, dynamic>{
           'detections_found': 0, 
           'inference_ms': 0,
           'pure_inference_ms': 0,
           't_preprocess': 0, 
           't_inference': 0,
           't_flatten': 0,
           't_nms': 0,
           't_transfer': tTransfer, // [NEW]
           't_serial': tSerial,     // [NEW]
           'use_gpu': _gpuEnabled,
        } 
      };
      
      if (interpreterPet == null) {
        // Error handling
      }

      try {
        final List<List<dynamic>> allDetections = [];
        final List<List<double>> petKeypointsList = [];
        final List<List<double>> humanKeypointsList = [];
        double maxConf = 0.0;
        
        // --- Helper: Flatten 3D List to Float32List ---
        void _flattenTo(List<dynamic> src3D, Float32List dstFlat) {
            int idx = 0;
            try {
               final batch0 = src3D[0] as List<dynamic>;
               final int rows = batch0.length;
               if (rows == 0) return;
               final row0 = batch0[0] as List<dynamic>;
               final int cols = row0.length;
               
               for(int r=0; r<rows; r++) {
                   final List<dynamic> row = batch0[r]; 
                   for(int c=0; c<cols; c++) {
                       dstFlat[idx++] = (row[c] as num).toDouble();
                   }
               }
            } catch (e) { }
        }

        // --- Model A: Pet Pose (Always Run) ---
        if (interpreterPet != null && _petOutput3D != null) {
          try {
            const int targetW = 640;
            const int targetH = 640;
            const int numPixels = targetW * targetH * 3;
            
            final inputTensor = interpreterPet!.getInputTensor(0);
            final outputTensor = interpreterPet!.getOutputTensor(0);
            
            // 1. Buffers
            if (_inputFloatBuffer == null || _inputFloatBuffer!.length != numPixels) {
               _inputFloatBuffer = Float32List(numPixels);
               _inputQuantBuffer = Uint8List(numPixels); 
            }
            
            // 2. Preprocess
            final swPrep = Stopwatch()..start();
            convertYUVToFloat32Tensor(
                rawData, targetW, targetH, rotation, 
                reuseBuffer: _inputFloatBuffer
            );
            swPrep.stop();
            result['debug_info']['t_preprocess'] = swPrep.elapsedMilliseconds;
            
            // 3. Run Inference
            final dynamic inputObj = _inputFloatBuffer; // Float model
            
            final outputShape = outputTensor.shape; 
            final int outputSize = outputShape.reduce((a, b) => a * b);
            if (_outputBufferPet == null || _outputBufferPet!.length != outputSize) {
               _outputBufferPet = Float32List(outputSize);
            }
            
            final swInference = Stopwatch()..start();
            // [Optim] Zero-Copy Inference: Direct Buffer Access
            interpreterPet!.run(_inputFloatBuffer!.buffer.asUint8List(), _outputBufferPet!.buffer.asUint8List());
            swInference.stop();
            result['debug_info']['t_inference'] = swInference.elapsedMilliseconds;
            
            // [Optim] Flatten step removed (Direct Output)
            result['debug_info']['t_flatten'] = 0;
            
            final swNMS = Stopwatch()..start();
            final detections = nonMaxSuppression(
                _outputBufferPet!, 3, 0.55, 0.25, // [Tuning] Lowered to 0.25
                keypointNum: 17, shape: outputShape 
            );
            swNMS.stop();
            result['debug_info']['t_nms'] = swNMS.elapsedMilliseconds;
            result['debug_info']['detections_found'] = detections.length;

            // [NEW] Top-1 Filtering for Pets
            dynamic bestPetDet;
            double bestPetScore = -1.0;

            for (var det in detections) {
               int mappedCls = 16; 
               if (det.classIndex == 1) mappedCls = 15; 
               if (det.classIndex == 2) mappedCls = 14; 
               
               // Check confidence
               if (det.score > bestPetScore) {
                   bestPetScore = det.score;
                   bestPetDet = {
                       'det': det,
                       'mappedCls': mappedCls
                   };
               }
            }

            if (bestPetDet != null) {
               final det = bestPetDet['det'];
               final mappedCls = bestPetDet['mappedCls'];
               
               allDetections.add([det.box[0], det.box[1], det.box[2], det.box[3], det.score, mappedCls.toDouble()]);
               if (det.keypoints != null) {
                  final List<double> normalizedKpts = [];
                  for (int k = 0; k < 17; k++) {
                     normalizedKpts.add(det.keypoints![k*3]);
                     normalizedKpts.add(det.keypoints![k*3+1]);
                     normalizedKpts.add(det.keypoints![k*3+2]);
                  }
                  petKeypointsList.add(normalizedKpts);
               }
               if (det.score > maxConf) maxConf = det.score;
            }
          } catch (e, stack) { 
             result['error'] = (result['error'] ?? "") + "[PetErr] $e\n";
             log("Pet Model Error: $e");
          }
        }

        // --- Model B: Object (Interleaved) ---
        bool runObject = (mode != 'interaction' && interpreterObj != null && _objOutput3D != null);
        // [User Request] Run Object Model EVERY frame (Disable skip)
        // if (runObject && (id % 3 != 0)) runObject = false;

        if (runObject) {
           try {
            final outputTensor = interpreterObj!.getOutputTensor(0);
            final outputShape = outputTensor.shape; 
            final int outputSize = outputShape.reduce((a, b) => a * b);
            
            if (_outputBufferObj == null || _outputBufferObj!.length != outputSize) {
                _outputBufferObj = Float32List(outputSize);
            }
           
            interpreterObj!.run(_inputFloatBuffer!.buffer.asUint8List(), _outputBufferObj!.buffer.asUint8List()); 
            // Flatten removed (Zero Copy) 
            final detections = nonMaxSuppression(
               _outputBufferObj!, 80, 0.55, 0.40, shape: outputShape
            );
            
            const Set<int> allowedProps = {29, 32, 39, 41, 45, 46, 47, 48, 49, 50, 51, 77};
            
             // [NEW] Top-1 Per Class Filtering for Props
             final Map<int, dynamic> bestProps = {};
             
             // 1. Collect Best Det Per Class
             for (var det in detections) {
                final clsId = det.classIndex;
                if (clsId == 0 || clsId == 14 || clsId == 15 || clsId == 16) continue;
                if (!allowedProps.contains(clsId)) continue; 

                if (!bestProps.containsKey(clsId) || det.score > bestProps[clsId].score) {
                    bestProps[clsId] = det;
                }
             }
             
             // 2. Process Filters & Persistence
             final Set<int> capturedClasses = bestProps.keys.toSet();
             final Set<int> allKnownClasses = {...lastPropBoxes.keys, ...capturedClasses};

             for (int clsId in allKnownClasses) {
                 bool isFresh = capturedClasses.contains(clsId);
                 
                 // A. Fresh Detection
                 if (isFresh) {
                     var rawDet = bestProps[clsId]!;
                     
                     // Init Filter
                     if (!objFilters.containsKey(clsId)) {
                        objFilters[clsId] = OneEuroFilter(minCutoff: 0.1, beta: 0.05, dCutoff: 1.0);
                     }
                     
                     // Apply Filter [x1, y1, x2, y2]
                     final filter = objFilters[clsId]!;
                     final now = DateTime.now().millisecondsSinceEpoch;
                     
                     // Center + Size smoothing (More stable than corners)
                     double rawCx = (rawDet.box[0] + rawDet.box[2]) / 2;
                     double rawCy = (rawDet.box[1] + rawDet.box[3]) / 2;
                     double rawW = rawDet.box[2] - rawDet.box[0];
                     double rawH = rawDet.box[3] - rawDet.box[1];
                     
                     // We filter 4 independent variables? Or corners? 
                     // Simple corner filtering is easier to implement with 1 box filter? 
                     // But OneEuroFilter is scalar. We need 4 filters or filter sequentially.
                     // Let's filter corners x1,y1,x2,y2 for simplicity.
                     // Ideally we need 4 filter instances per object? No, OneEuroFilter is stateful for ONE value.
                     // [CRITICAL] OneEuroFilter maintains state for ONE stream. 
                     // We cannot use 1 filter for 4 coordinates. We need 4 filters per Object!
                     // Re-thinking: Just use naive smoothing or create a BoxFilter class.
                     // Or just use "Ghosting" which solves the "Disappearing" issue (Flickering presence).
                     // Coordinate jitter is less of an issue than presence flickering.
                     // Let's stick to PRESENCE Persistence (Ghost Tracking) first.
                     
                     // Update State
                     lastPropBoxes[clsId] = [rawDet.box[0], rawDet.box[1], rawDet.box[2], rawDet.box[3], rawDet.score, clsId.toDouble()];
                     propMissingCounts[clsId] = 0;
                     
                     allDetections.add([rawDet.box[0], rawDet.box[1], rawDet.box[2], rawDet.box[3], rawDet.score, clsId.toDouble()]);
                 } 
                 // B. Missing (Ghost)
                 else {
                     int missing = propMissingCounts[clsId] ?? 0;
                     if (missing < MAX_PROP_MISSING) {
                         // Recover Last Box
                         final lastDet = lastPropBoxes[clsId]!;
                         
                         // Add Ghost Box (Maybe lower score slightly?)
                         // We keep original score to prevent logic rejection
                         allDetections.add(lastDet);
                         
                         propMissingCounts[clsId] = missing + 1;
                     } else {
                         // Expired
                         lastPropBoxes.remove(clsId);
                         propMissingCounts.remove(clsId);
                         objFilters.remove(clsId);
                     }
                 }
             }
           } catch (e) { 
              result['error'] = (result['error'] ?? "") + "[ObjErr] $e\n";
              log("Obj Model Error: $e");
           }
         } else {
             // [NEW] Skipped Frame Logic -> CARRY OVER LAST KNOWN PROPS
             // Do NOT decay missing count, just replay last good frame.
             for (int clsId in lastPropBoxes.keys) {
                 final lastDet = lastPropBoxes[clsId]!;
                 allDetections.add(lastDet);
             }
         }

        // --- Model C: Human Pose ---
        if (mode == 'interaction' && interpreterHuman != null && _humanOutput3D != null) {
          try {
            final outputTensor = interpreterHuman!.getOutputTensor(0);
            final outputShape = outputTensor.shape; 
            final int outputSize = outputShape.reduce((a, b) => a * b);
            if (_outputBufferHuman == null || _outputBufferHuman!.length != outputSize) {
                _outputBufferHuman = Float32List(outputSize);
            }
            interpreterHuman!.run(_inputFloatBuffer!.buffer.asUint8List(), _outputBufferHuman!.buffer.asUint8List());
            // Flatten removed (Zero Copy)
            
            final detections = nonMaxSuppression(
               _outputBufferHuman!, 1, 0.55, 0.40, keypointNum: 17, shape: outputShape
            );
            
            // [NEW] Top-1 Filtering for Human (Already NMS limit 1, but reinforcing)
            if (detections.isNotEmpty) {
               // Only take the first one (Best Score)
               var det = detections[0];
               
               allDetections.add([det.box[0], det.box[1], det.box[2], det.box[3], det.score, 0.0]);
               if (det.keypoints != null) {
                  final List<double> normalizedKpts = [];
                  for (int k = 0; k < 17; k++) {
                     normalizedKpts.add(det.keypoints![k*3]);
                     normalizedKpts.add(det.keypoints![k*3+1]);
                     normalizedKpts.add(det.keypoints![k*3+2]);
                  }
                  humanKeypointsList.add(normalizedKpts);
               }
            }
          } catch (e) { 
             result['error'] = (result['error'] ?? "") + "[HumanErr] $e\n";
             log("Human Model Error: $e");
          }
        }
        
        if (allDetections.isNotEmpty) {
           result['success'] = true;
           result['bbox'] = allDetections;
           result['pet_keypoints'] = petKeypointsList;
           result['human_keypoints'] = humanKeypointsList;
           result['conf_score'] = maxConf;
        }

      } catch (e, stack) {
        // [Fix] Catch block that was missing
        result['error'] = (result['error'] ?? "") + "CRASH: $e";
        initData.sendPort.send({'log': "Edge Error: $e\nStack: $stack"});
      }
      
      sw.stop();
      
      // Update inference time
      result['debug_info']['inference_ms'] = sw.elapsedMilliseconds;
      result['debug_info']['pure_inference_ms'] = sw.elapsedMilliseconds - tTransfer - tSerial; 
      
      initData.sendPort.send(result);
    }
    // ...
    else if (cmd == Cmd.close) {
      interpreterPet?.close();
      interpreterObj?.close();
      interpreterHuman?.close();
      Isolate.exit();
    }
    else if (cmd == Cmd.ping) {
      // [Fix] Ping should verify MODEL STATE, not just Isolate liveness.
      bool isReady = (interpreterPet != null);
      initData.sendPort.send({'pong': isReady});
    }
  });
}

// --- Helper Code ---

/// Quantize Logic for Int8/UInt8 Inputs
Object _prepareInputTensor(Float32List floatInput, Tensor inputTensor, {Uint8List? reuseQuantBuffer}) {
  // If input is Float32, just reshape (No copy)
  if (inputTensor.type == TfLiteType.kTfLiteFloat32 || 
      inputTensor.type == TfLiteType.kTfLiteNoType) {
    return floatInput.reshape(inputTensor.shape);
  }
  
  // If input is Uint8 (Image Quantized)
  if (inputTensor.type == TfLiteType.kTfLiteUInt8) {
    final params = inputTensor.params;
    double scale = params.scale;
    int zeroPoint = params.zeroPoint;
    
    // Safety
    if (scale == 0.0) scale = 1.0; 
    
    // Heuristic: If scale > 0.1, it expects [0, 255] domain.
    bool needRescale = scale > 0.1;
    
    final size = floatInput.length;
    // Use reused buffer if available
    final uint8 = reuseQuantBuffer ?? Uint8List(size);
    
    for (int i = 0; i < size; i++) {
       double val = floatInput[i];
       if (needRescale) val *= 255.0;
       
       // Quantize: q = float / scale + zp
       uint8[i] = (val / scale + zeroPoint).round().clamp(0, 255);
    }
    return uint8.reshape(inputTensor.shape);
  }
  
  // If input is Int8
  if (inputTensor.type == TfLiteType.kTfLiteInt8) {
    final params = inputTensor.params;
    double scale = params.scale;
    int zeroPoint = params.zeroPoint;
    if (scale == 0.0) scale = 1.0;
    
    final size = floatInput.length;
    final int8 = Int8List(size);
    for (int i = 0; i < size; i++) {
       int8[i] = (floatInput[i] / scale + zeroPoint).round().clamp(-128, 127);
    }
    return int8.reshape(inputTensor.shape);
  }
  
  // Default fallback
  return floatInput.reshape(inputTensor.shape);
}

