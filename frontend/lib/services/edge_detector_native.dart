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

  Future<Map<String, dynamic>> processFrame(CameraImage image, String mode, int rotationAngle) async {
    if (_sendPort == null) return {};

    final completer = Completer<Map<String, dynamic>>();

    final id = _requestIdCounter++;
    _requests[id] = completer;

    // Convert CameraImage to transferable map (bytes)
    // We do NOT use compute here, we send raw bytes to the isolate directly
    final rawData = {
      'width': image.width,
      'height': image.height,
      'planes': image.planes.map((p) => {
        'bytes': p.bytes,
        'bytesPerRow': p.bytesPerRow,
        'bytesPerPixel': p.bytesPerPixel
      }).toList(),
    };

    _sendPort!.send({
      'cmd': Cmd.detect,
      'req_id': id,
      'data': rawData,
      'mode': mode,
      'rotation': rotationAngle // [NEW]
    });

    // [Fix] INCREASE TIMEOUT to 3000ms (1280px inference is heavy)
    return completer.future.timeout(const Duration(milliseconds: 3000), onTimeout: () {
       _requests.remove(id);
       _kill(); 
       throw TimeoutException("Edge AI Isolate Hung (>3000ms)");
    });
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
// --- Isolate Entry Point ---
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
  
  receivePort.listen((message) async {
    final cmd = message['cmd'] as Cmd;
    
    if (cmd == Cmd.init) {
      log("Cmd.init [STRICT MODE]");
      try {
        InterpreterOptions? options; 
        
        // --- 1. Pet Model ---
        log("Loading Pet Model...");
        final petBytes = message['petBytes'] as Uint8List;
        _buffers.add(petBytes);
        interpreterPet = Interpreter.fromBuffer(petBytes, options: options);
        
        // [Strict Init] Force 640x640x3 to ensure 4D Tensor for Conv2D
        // Without this, TFLite defaults to Flat 1D [1228800], causing crashes.
        log("Forcing Resize to [1, 640, 640, 3]...");
        interpreterPet!.resizeInputTensor(0, [1, 640, 640, 3]);
        interpreterPet!.allocateTensors();
        
        _petInputShape = interpreterPet!.getInputTensor(0).shape;
        log("Pet Allocated. Input: $_petInputShape"); // Should be [1, 640, 640, 3]

        // --- 2. Object Model ---
        log("Loading Obj Model...");
        final objBytes = message['objBytes'] as Uint8List;
        _buffers.add(objBytes);
        interpreterObj = Interpreter.fromBuffer(objBytes, options: options);
        interpreterObj?.resizeInputTensor(0, [1, 640, 640, 3]); // Force consistency
        interpreterObj?.allocateTensors();
        log("Obj OK.");
        
        // --- 3. Human Model ---
        log("Loading Human Model...");
        final humanBytes = message['humanBytes'] as Uint8List;
        _buffers.add(humanBytes);
        interpreterHuman = Interpreter.fromBuffer(humanBytes, options: options);
        interpreterHuman?.resizeInputTensor(0, [1, 640, 640, 3]); 
        interpreterHuman?.allocateTensors(); 
        log("Human OK.");

        log("All Models Ready (Strict Mode).");
        initData.sendPort.send({'init_done': true});
        
      } catch (e, stack) {
        log("Init Error: $e");
        log("Stack: $stack");
        initData.sendPort.send({'init_done': false, 'error': e.toString(), 'stack': stack.toString()});
      }
    } 
    else if (cmd == Cmd.detect) {
      final sw = Stopwatch()..start(); // [DEBUG] Profile
      final id = message['req_id'];
      final rawData = message['data'];
      final mode = message['mode'];
      final rotation = message['rotation'] ?? 0;
      
      final result = <String, dynamic>{
        'req_id': id,
        'success': false,
        'bbox': [], // Final merged list
        'pet_keypoints': [], // [NEW]
        'human_keypoints': [], // [NEW]
        'conf_score': 0.0,
        'debug_info': {} // [NEW]
      };
      
      if (interpreterPet == null) {
        result['error'] = "Models not loaded (Init Failed)";
        initData.sendPort.send(result);
        return;
      }

      try {
        final List<List<dynamic>> allDetections = [];
        final List<List<double>> petKeypointsList = [];
        final List<List<double>> humanKeypointsList = [];
        double maxConf = 0.0;
        
        result['debug_info'] = {
           'input_type': 'N/A', 'output_type': 'N/A', 
           'detections_found': 0, 'parsing_mode': 'Init',
           'inference_ms': 0, 'pure_inference_ms': 0
        };

        // --- Helper: Flatten 3D List to Float32List ---
        void _flattenTo(List<dynamic> src3D, Float32List dstFlat) {
            int idx = 0;
            try {
              for (var batch in src3D) {
                 for (var row in batch) {
                    if (row is List) {
                       for (var val in row) {
                          if (idx < dstFlat.length) {
                             dstFlat[idx++] = (val as num).toDouble();
                          }
                       }
                    }
                 }
              }
            } catch (e) {
               // Silently fail or minimal log to maximize perf
            }
        }

        // --- Model A: Pet Pose (Always Run) ---
        if (interpreterPet != null) {
          try {
            const int targetW = 640;
            const int targetH = 640;
            const int numPixels = targetW * targetH * 3;
            
            final inputTensor = interpreterPet!.getInputTensor(0);
            final outputTensor = interpreterPet!.getOutputTensor(0);
            
            result['debug_info']['input_type'] = inputTensor.type.toString();
            
            // 1. Buffers
            if (_inputFloatBuffer == null || _inputFloatBuffer!.length != numPixels) {
               _inputFloatBuffer = Float32List(numPixels);
               _inputQuantBuffer = Uint8List(numPixels); 
            }
            
            // 2. Preprocess
            convertYUVToFloat32Tensor(
                rawData, targetW, targetH, rotation, 
                reuseBuffer: _inputFloatBuffer
            );
            
            // 3. Prepare Input
            final dynamic inputObj = _prepareInputTensor(
                _inputFloatBuffer!, 
                inputTensor,
                reuseQuantBuffer: _inputQuantBuffer
            );

            // 4. Output Buffer
            final outputShape = outputTensor.shape; 
            final int outputSize = outputShape.reduce((a, b) => a * b);
            
            if (_outputBufferPet == null || _outputBufferPet!.length != outputSize) {
               _outputBufferPet = Float32List(outputSize);
            }
            
            // Create 3D Container
            final outputTensor3D = List.generate(
              outputShape[0], 
              (_) => List.generate(
                outputShape[1], 
                (_) => List.filled(outputShape[2], 0.0)
              )
            );
            
            // 5. Run Inference
            final swInference = Stopwatch()..start();
            interpreterPet!.run(inputObj, outputTensor3D);
            swInference.stop();
            result['debug_info']['pure_inference_ms'] = swInference.elapsedMilliseconds;
            
            // [CRITICAL FIX] Sync back from 3D output to Flat Buffer
            // Because reshape() created a copy structure.
            _flattenTo(outputTensor3D, _outputBufferPet!);
            
            // [Verification] Max Value Check
            double currentMax = 0.0;
            for(final v in _outputBufferPet!) {
               if (v > currentMax) currentMax = v;
            }
            print("[ISO-DEBUG-V2] Output Max: $currentMax");
            result['debug_info']['measured_max'] = currentMax;

            // [Debug] Check first 10 values
            List<double> sample = [];
            for(int i=0; i<min(10, outputSize); i++) sample.add(_outputBufferPet![i]);
            print("[ISO-DEBUG] Pet Output Sample: $sample");
            result['debug_info']['output_sample'] = sample.toString();

            // [Debug] Output Stats
            result['debug_info']['output_shape'] = outputShape.toString();

            // 6. Parse Output (Pet: 3 Classes, 17 Keypoints)
            final detections = nonMaxSuppression(
                _outputBufferPet!,  
                3, // Classes
                0.50, // [High Thresh] 0.50 for clean output
                0.40, // [Strict NMS] 0.40
                keypointNum: 17,
                shape: outputShape 
            );
            
            result['debug_info']['detections_found'] = detections.length;
            result['debug_info']['parsing_mode'] = 'Raw (Stride)';

            for (var det in detections) {
               int mappedCls = 16; 
               if (det.classIndex == 1) mappedCls = 15; 
               if (det.classIndex == 2) mappedCls = 14; 
               
               // [Fix] No internal division needed, NMS returns Normalized (0-1)
               allDetections.add([
                 det.box[0], det.box[1], det.box[2], det.box[3],
                 det.score,
                 mappedCls.toDouble()
               ]);
               
               if (det.keypoints != null) {
                  final List<double> normalizedKpts = [];
                  for (int k = 0; k < 17; k++) {
                     // NMS already normalized these
                     normalizedKpts.add(det.keypoints![k*3]);
                     normalizedKpts.add(det.keypoints![k*3+1]);
                     normalizedKpts.add(det.keypoints![k*3+2]);
                  }
                  petKeypointsList.add(normalizedKpts);
               }
               if (det.score > maxConf) maxConf = det.score;
            }
          } catch (e, stack) {
             print("Model A (Pet) Failed: $e");
             print("Stack: $stack");
             result['debug_info']['pet_error'] = e.toString();
          }
        }

        // --- Model B: Object (Run if NOT interaction) ---
        if (mode != 'interaction' && interpreterObj != null) {
          try {
            const int targetW = 640;
            const int targetH = 640;
            
            final inputTensor = interpreterObj!.getInputTensor(0);
            final outputTensor = interpreterObj!.getOutputTensor(0);
            
            final dynamic inputObj = _prepareInputTensor(
                _inputFloatBuffer!, 
                inputTensor,
                reuseQuantBuffer: _inputQuantBuffer
            );
            
            final outputShape = outputTensor.shape; 
            final int outputSize = outputShape.reduce((a, b) => a * b);
            
            if (_outputBufferObj == null || _outputBufferObj!.length != outputSize) {
                _outputBufferObj = Float32List(outputSize);
            }
            // 3D Container
            final outputTensor3D = List.generate(
              outputShape[0], 
              (_) => List.generate(
                outputShape[1], 
                (_) => List.filled(outputShape[2], 0.0)
              )
            );
            
            interpreterObj!.run(inputObj, outputTensor3D);
            _flattenTo(outputTensor3D, _outputBufferObj!);
  
            // Obj: 80 Classes, 0 Keypoints
            final detections = nonMaxSuppression(
               _outputBufferObj!,
               80, 
               0.50, // [High Thresh] 0.50
               0.40, // [Strict NMS] 0.40
               shape: outputShape
            );
            
            result['debug_info']['obj_count'] = detections.length;
            
            for (var det in detections) {
               if ([0, 14, 15, 16].contains(det.classIndex)) continue; 
               
               allDetections.add([
                 det.box[0], det.box[1], det.box[2], det.box[3],
                 det.score,
                 det.classIndex.toDouble()
               ]);
            }
          } catch (e) {
            print("Model B (Obj) Failed: $e");
            result['debug_info']['obj_error'] = e.toString();
          }
        }

        // --- Model C: Human Pose (Run if interaction) ---
        if (mode == 'interaction' && interpreterHuman != null) {
          try {
            const int targetSize = 640;
            
            final inputTensor = interpreterHuman!.getInputTensor(0);
            final outputTensor = interpreterHuman!.getOutputTensor(0);

            final dynamic inputObj = _prepareInputTensor(
                _inputFloatBuffer!, 
                inputTensor,
                reuseQuantBuffer: _inputQuantBuffer
            );
            
            final outputShape = outputTensor.shape; 
            final int outputSize = outputShape.reduce((a, b) => a * b);
            
            if (_outputBufferHuman == null || _outputBufferHuman!.length != outputSize) {
                _outputBufferHuman = Float32List(outputSize);
            }
            // 3D Container
            final outputTensor3D = List.generate(
              outputShape[0], 
              (_) => List.generate(
                outputShape[1], 
                (_) => List.filled(outputShape[2], 0.0)
              )
            );
            
            interpreterHuman!.run(inputObj, outputTensor3D);
            _flattenTo(outputTensor3D, _outputBufferHuman!);
            
            // Human: 1 Class, 17 Keypoints
            final detections = nonMaxSuppression(
               _outputBufferHuman!,
               1, 
               0.50, // [High Thresh] 0.50
               0.40, // [Strict NMS] 0.40
               keypointNum: 17, 
               shape: outputShape
            );
            
            result['debug_info']['human_count'] = detections.length;
            
            for (var det in detections) {
               allDetections.add([
                 det.box[0], det.box[1], det.box[2], det.box[3],
                 det.score,
                 0.0 
               ]);
               
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
            print("Model C (Human) Failed: $e");
            result['debug_info']['human_error'] = e.toString();
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
        print("Edge Inference Error: $e");
        print("Stack: $stack");
        result['error'] = "Inference Error: $e"; 
        result['stack'] = stack.toString();
      }
      
      sw.stop();
      print("[ISO-PERF] === TOTAL Time (all steps): ${sw.elapsedMilliseconds}ms ===");
      
      // [FIX] Report ONLY pure inference time to UI (not total processing time)
      // Total time includes YUV conversion (~1500ms), which inflates the number
      // Pure inference should be 100-300ms
      result['debug_info']['inference_ms'] = result['debug_info']['pure_inference_ms'] ?? sw.elapsedMilliseconds;
      
      initData.sendPort.send(result);
    }
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

