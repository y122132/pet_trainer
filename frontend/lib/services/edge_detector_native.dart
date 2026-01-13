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
        final petData = await rootBundle.load('assets/models/pet_pose_float32.tflite');
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

        // --- Model A: Pet Pose (Always Run) ---
        try {
          const int targetW = 640;
          const int targetH = 640;
          
          final inputTensor = interpreterPet!.getInputTensor(0);
          final outputTensor = interpreterPet!.getOutputTensor(0);
          
          // [CRITICAL] Extract quantization parameters
          final inputType = inputTensor.type.toString();
          final outputType = outputTensor.type.toString();
          final inputShape = inputTensor.shape.toString();
          final outputShapeList = outputTensor.shape;
          
          // Quantization parameters (if exists)
          String inputQuantInfo = "None";
          String outputQuantInfo = "None";
          
          try {
            final inputParams = inputTensor.params;
            if (inputParams != null) {
              inputQuantInfo = "Scale: ${inputParams.scale}, Zero: ${inputParams.zeroPoint}";
            }
          } catch (e) {
            inputQuantInfo = "N/A";
          }
          
          try {
            final outputParams = outputTensor.params;
            if (outputParams != null) {
              outputQuantInfo = "Scale: ${outputParams.scale}, Zero: ${outputParams.zeroPoint}";
            }
          } catch (e) {
            outputQuantInfo = "N/A";
          }
          
          print("[ISO-DEBUG] Pet Model - Input Shape: $inputShape, Type: $inputType");
          print("[ISO-DEBUG] Input Quantization: $inputQuantInfo");
          print("[ISO-DEBUG] Output Shape: $outputShapeList, Type: $outputType");
          print("[ISO-DEBUG] Output Quantization: $outputQuantInfo");
          
          // [DEBUG] Populate result info for UI log
          result['debug_info']['shape'] = inputShape;
          result['debug_info']['input_type'] = inputType;
          result['debug_info']['output_type'] = outputType;
          result['debug_info']['input_quant'] = inputQuantInfo;
          result['debug_info']['output_quant'] = outputQuantInfo;

          // [Restored] Model Expects Float32 (Confirmed by User Screenshot)
          // We must provide Float32 input. TFLite handles quantization internally if needed.
          
          final swPreprocess = Stopwatch()..start();
          final floatInput = convertYUVToFloat32Tensor(rawData, targetW, targetH, rotation);
          swPreprocess.stop();
          print("[ISO-PERF] Preprocessing (YUV→RGB+Normalize): ${swPreprocess.elapsedMilliseconds}ms");
          
          // [CRITICAL] Validate input data
          final inputSample = floatInput.sublist(0, min(30, floatInput.length)).map((v) => v.toStringAsFixed(4)).join(', ');
          final inputMin = floatInput.reduce((a, b) => a < b ? a : b);
          final inputMax = floatInput.reduce((a, b) => a > b ? a : b);
          
          result['debug_info']['input_sample'] = inputSample;
          result['debug_info']['input_min'] = inputMin;
          result['debug_info']['input_max'] = inputMax;
          
          print("[ISO-DEBUG] Input Sample (first 30 values): $inputSample");
          print("[ISO-DEBUG] Input Range: Min=$inputMin, Max=$inputMax (Expected: 0.0-1.0)");
          
          if (floatInput.length != targetW * targetH * 3) {
             throw Exception("Input Size Mismatch! Got ${floatInput.length}, Need ${targetW*targetH*3}");
          }
          
          // [FIX] Reshape to 4D tensor [1, 640, 640, 3]
          final swReshape = Stopwatch()..start();
          final inputTensor4D = floatInput.reshape([1, targetW, targetH, 3]);
          swReshape.stop();
          print("[ISO-PERF] Reshape Input: ${swReshape.elapsedMilliseconds}ms");
          
          // [DEBUG] Validate input data range
          final sampleSize = floatInput.length < 9 ? floatInput.length : 9;
          final sampleValues = floatInput.sublist(0, sampleSize);
          final minVal = sampleValues.reduce((a, b) => a < b ? a : b);
          final maxVal = sampleValues.reduce((a, b) => a > b ? a : b);
          print("[ISO-DEBUG] Input Sample (first 3 pixels RGB): ${sampleValues.map((v) => v.toStringAsFixed(3)).join(', ')}");
          print("[ISO-DEBUG] Input Range: Min=$minVal, Max=$maxVal (Expected: 0.0-1.0)");
          
          // [NEW] Convert Float32 input to PNG for visualization
          // [CRITICAL PERF] PNG encoding is VERY SLOW (~900ms)
          // Only generate every 30 frames to maintain performance
          _pngFrameCounter++;
          
          if (_pngFrameCounter % 30 == 1) { // Only every 30 frames
             try {
                // Convert Float32 (0-1) to Uint8 (0-255)
                final uint8Data = Uint8List(floatInput.length);
                for (int i = 0; i < floatInput.length; i++) {
                   uint8Data[i] = (floatInput[i] * 255).clamp(0, 255).toInt();
                }
                
                // Encode as PNG (640x640 RGB)
                final image = img.Image.fromBytes(
                   width: targetW,
                   height: targetH,
                   bytes: uint8Data.buffer,
                   numChannels: 3,
                );
                final pngBytes = img.encodePng(image);
                result['debug_info']['input_image_png'] = pngBytes;
             } catch (e) {
                print("[ISO-ERROR] Failed to encode input image: $e");
             }
          }
           
          final outputShape = outputTensor.shape; 
          final outputBuffer = Float32List(outputShape.reduce((a, b) => a * b));
          
          // [FIX] Reshape output buffer to match expected shape
          // TFLite run() requires exact shape matching
          final outputTensor3D = outputBuffer.reshape(outputShape);
          
          // [FIX] Remove unnecessary allocateTensors() - already allocated in init
          // Calling this every frame causes overhead and instability
          
          // [CRITICAL] Measure ONLY inference time
          final swInference = Stopwatch()..start();
          interpreterPet!.run(inputTensor4D, outputTensor3D);
          swInference.stop();
          final pureInferenceMs = swInference.elapsedMilliseconds;
          print("[ISO-PERF] *** Pure Inference: ${pureInferenceMs}ms ***");
          
          // Store pure inference time for UI
          result['debug_info']['pure_inference_ms'] = pureInferenceMs;

          List<DetectionResult> detections = [];

          // [CRITICAL] Parse Model Output
          // Output Shape: [1, 300, 57] for pet_pose_int8.tflite
          // Format: 57 = 4(bbox) + 1(conf) + 1(cls) + 51(17 keypoints * 3)
          
          final swParsing = Stopwatch()..start();
          
          // Sample output for debugging
          final outputSample = outputBuffer.sublist(0, min(20, outputBuffer.length)).map((v) => v.toStringAsFixed(4)).join(', ');
          
          // [CRITICAL] Check if output has ANY non-zero values
          final outputMin = outputBuffer.reduce((a, b) => a < b ? a : b);
          final outputMax = outputBuffer.reduce((a, b) => a > b ? a : b);
          final nonZeroCount = outputBuffer.where((v) => v.abs() > 0.0001).length;
          
          result['debug_info']['output_sample'] = outputSample;
          result['debug_info']['output_shape'] = outputShape.toString();
          result['debug_info']['output_total'] = outputBuffer.length;
          result['debug_info']['output_min'] = outputMin;
          result['debug_info']['output_max'] = outputMax;
          result['debug_info']['output_nonzero'] = nonZeroCount;
          
          print("[ISO-DEBUG] Output Min: $outputMin, Max: $outputMax, NonZero: $nonZeroCount/${outputBuffer.length}");
          
          // Check if this is NMS output (sorted by conf) or Raw output
          // NMS Mode: First few detections have highest confidence
          // Raw Mode: Need to scan all 300 anchors
          
          bool isNMSMode = false;
          if (outputShape[1] <= 300) {
             // Likely NMS output (e.g., 300 detections, pre-sorted)
             isNMSMode = true;
             result['debug_info']['parsing_mode'] = 'NMS';
          } else {
             result['debug_info']['parsing_mode'] = 'Raw';
          }
          
          if (isNMSMode) {
              // Pre-processed NMS mode
              print("[ISO-DEBUG] Parsing NMS output mode...");
              detections = parseNMSOutput(
                outputBuffer, 
                0.001, // [TEST] Minimum threshold to detect ANY output
                keypointNum: 17
              );
          } else {
              // Raw Output (Batch, Features, Anchors)
              print("[ISO-DEBUG] Parsing Raw output mode...");
              detections = nonMaxSuppression(
                outputBuffer,  
                3, 
                0.15, 0.45,
                keypointNum: 17,
                shape: outputShape 
              );
          }
          swParsing.stop();
          
          // [CRITICAL] Log detection results for UI
          result['debug_info']['detections_found'] = detections.length;
          result['debug_info']['parsing_time_ms'] = swParsing.elapsedMilliseconds;
          
          print("[ISO-RESULT] Pet detections found: ${detections.length}");
           print("[ISO-RESULT] Pet detections found: ${detections.length}");

          for (var det in detections) {
             int mappedCls = 16; 
             if (det.classIndex == 1) mappedCls = 15; 
             if (det.classIndex == 2) mappedCls = 14; 
             
             // Normalize by the actual target sizes used
             allDetections.add([
               det.box[0] / targetW, det.box[1] / targetH, det.box[2] / targetW, det.box[3] / targetH,
               det.score,
               mappedCls.toDouble()
             ]);
             
             if (det.keypoints != null) {
                final List<double> normalizedKpts = [];
                for (int k = 0; k < 17; k++) {
                   double kx = det.keypoints![k*3];
                   double ky = det.keypoints![k*3+1];
                   double kc = det.keypoints![k*3+2];
                   
                   normalizedKpts.add(kx / targetW);
                   normalizedKpts.add(ky / targetH);
                   normalizedKpts.add(kc);
                }
                petKeypointsList.add(normalizedKpts);
             }
             
             if (det.score > maxConf) maxConf = det.score;
          }
        } catch (e, stack) {
             print("Model A (Pet) Failed: $e");
             result['error'] = "Pet Model Error: $e"; 
             result['stack'] = stack.toString();
        }

        // --- Model B: Object (Run if NOT interaction) ---
        if (mode != 'interaction' && interpreterObj != null) {
          try {
            const int targetW = 640;
            const int targetH = 640;
            
            // [FIX] Use Float32 input (model expects Float32, not Uint8)
            final floatInput = convertYUVToFloat32Tensor(rawData, targetW, targetH, rotation);
            final inputTensor4D = floatInput.reshape([1, targetW, targetH, 3]);
            
            final outputTensor = interpreterObj!.getOutputTensor(0);
            final shape = outputTensor.shape;
            
            final outputBuffer = Float32List(shape.reduce((a, b) => a * b));
            final outputTensor3D = outputBuffer.reshape(shape);
            
            // [FIX] Use run() with reshaped tensors
            interpreterObj!.run(inputTensor4D, outputTensor3D);
  
            final detections = nonMaxSuppression(
               outputBuffer,
               80, 
               0.15, 0.45,
               shape: shape
            );
            
            result['debug_info']['obj_count'] = detections.length;
            
            for (var det in detections) {
               allDetections.add([
                 det.box[0] / targetW, det.box[1] / targetH, det.box[2] / targetW, det.box[3] / targetH,
                 det.score,
                 det.classIndex.toDouble()
               ]);
            }
          } catch (e) {
            print("Model B (Obj) Failed: $e");
          }
        }

        // --- Model C: Human Pose (Run if interaction, 640px) ---
        if (mode == 'interaction' && interpreterHuman != null) {
          try {
            const targetSize = 640;
            
            // [FIX] Use Float32 input (model expects Float32, not Uint8)
            final floatInput = convertYUVToFloat32Tensor(rawData, targetSize, targetSize, rotation);
            final inputTensor4D = floatInput.reshape([1, targetSize, targetSize, 3]);
            
            final outputTensor = interpreterHuman!.getOutputTensor(0);
            final shape = outputTensor.shape;
            final outputBuffer = Float32List(shape.reduce((a, b) => a * b));
            final outputTensor3D = outputBuffer.reshape(shape);
            
            // [FIX] Use run() with reshaped tensors
            interpreterHuman!.run(inputTensor4D, outputTensor3D);
            
            // Parse output (still need to handle shape properly)
            final detections = nonMaxSuppression(
               outputBuffer,
               1, // Person Class
               0.30, 0.45,
               keypointNum: 17 // [NEW] Human Pose
            );
            
            result['debug_info']['human_count'] = detections.length; // [DEBUG]
            
            for (var det in detections) {
               // Person class is 0. Map to 0.
               allDetections.add([
                 det.box[0] / targetSize, det.box[1] / targetSize, det.box[2] / targetSize, det.box[3] / targetSize,
                 det.score,
                 0.0 // Person
               ]);
               
               // [NEW] Process Keypoints
               if (det.keypoints != null) {
                  final List<double> normalizedKpts = [];
                  for (int k = 0; k < 17; k++) {
                     double kx = det.keypoints![k*3];
                     double ky = det.keypoints![k*3+1];
                     double kc = det.keypoints![k*3+2];
                     
                     normalizedKpts.add(kx / targetSize);
                     normalizedKpts.add(ky / targetSize);
                     normalizedKpts.add(kc);
                  }
                  humanKeypointsList.add(normalizedKpts);
               }
            }
          } catch (e) {
            print("Model C (Human) Failed: $e");
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
        result['error'] = "Inference Error: $e"; // [DEBUG] Propagate error
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
Object _prepareInputTensor(Float32List floatInput, Tensor inputTensor) {
  // If input is Float32, just reshape
  if (inputTensor.type == TfLiteType.kTfLiteFloat32 || 
      inputTensor.type == TfLiteType.kTfLiteNoType) {
    return floatInput.reshape(inputTensor.shape);
  }
  
  // If input is Uint8 (Image Quantized)
  if (inputTensor.type == TfLiteType.kTfLiteUInt8) {
    final params = inputTensor.params;
    double scale = params.scale;
    int zeroPoint = params.zeroPoint;
    
    // Safety for 0 scale
    if (scale == 0.0) scale = 1.0; 
    
    // [Fix] Smart Input Scaling
    // TFLite Quantization often expects the "Real" value domain to match the training domain.
    // Case A: Model trained on [0, 255] images. Scale ~ 1.0 (Real domain 0-255).
    //         We provide [0, 1]. Result is black image. -> Need to multiply by 255.
    // Case B: Model trained on [0, 1] normalized. Scale ~ 0.0039 (Real domain 0-1).
    //         We provide [0, 1]. All good.
    // Heuristic: If scale > 0.1, it expects [0, 255].
    bool needRescale = scale > 0.1;
    
    final size = floatInput.length;
    final uint8 = Uint8List(size);
    for (int i = 0; i < size; i++) {
       double val = floatInput[i];
       if (needRescale) val *= 255.0;
       
       // float = (q - zp) * scale
       // q = float / scale + zp
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

