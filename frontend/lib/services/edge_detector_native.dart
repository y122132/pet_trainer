import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:pet_trainer_frontend/services/edge_utils.dart';

// --- Commands ---
enum Cmd { init, detect, close, ping }

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

  Future<void> initialize() async {
    // 1. Check if already initialized or stale
    if (_isolate != null && _sendPort != null) {
       // [Fix] Instead of killing, we reuse if healthy.
       bool isHealthy = await _checkHealth();
       if (isHealthy) {
          return; 
       }
       
       print("Edge AI Isolate Unhealthy/Stale! Restarting...");
       _kill();
    } else {
       // Ensure clean state if partial init
       _kill();
    }

    _initCompleter = Completer<void>();
    _receivePort = ReceivePort();
    
    // Pass RootIsolateToken for asset loading in background
    final rootToken = RootIsolateToken.instance;
    
    _isolate = await Isolate.spawn(
      _isolateEntry, 
      _IsolateInitData(_receivePort!.sendPort, rootToken!),
    );

    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _sendPort!.send({'cmd': Cmd.init}); // Load Models
      } else if (message is Map<String, dynamic>) {
        if (message.containsKey('init_done')) {
          if (message['init_done'] == true) {
             _initCompleter?.complete();
          } else {
             _initCompleter?.completeError(message['error'] ?? "Unknown Init Error");
          }
        } else if (message.containsKey('pong')) {
          _pingCompleter?.complete(true);
        } else if (message.containsKey('req_id')) {
          final id = message['req_id'];
          final completer = _requests.remove(id);
          completer?.complete(message);
        }
      }
    });

    return _initCompleter!.future;
  }
  
  // [NEW] Health Check
  Future<bool> _checkHealth() async {
      _pingCompleter = Completer<bool>();
      _sendPort?.send({'cmd': Cmd.ping});
      try {
        return await _pingCompleter!.future.timeout(const Duration(milliseconds: 200));
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
    
    // Reset completers
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
       _initCompleter!.completeError("Isolate Killed during Init");
       _initCompleter = null;
    }
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
        await initialize();
     }
  }
}

class _IsolateInitData {
  final SendPort sendPort;
  final RootIsolateToken rootToken;
  _IsolateInitData(this.sendPort, this.rootToken);
}

// --- Isolate Entry Point ---
void _isolateEntry(_IsolateInitData initData) async {
  // Initialize Background Channel
  try {
    BackgroundIsolateBinaryMessenger.ensureInitialized(initData.rootToken);
  } catch (_) {}
  
  final receivePort = ReceivePort();
  initData.sendPort.send(receivePort.sendPort);

  Interpreter? interpreterPet;
  Interpreter? interpreterObj;
  Interpreter? interpreterHuman;
  
  receivePort.listen((message) async {
    final cmd = message['cmd'] as Cmd;
    
    if (cmd == Cmd.init) {
      try {
        final options = InterpreterOptions();
        // [Safety] Disable delegates for debugging crashes (Int8 CPU fallback is safest)
        // if (Platform.isAndroid) options.addDelegate(XNNPackDelegate());
        
        // 1. Pet Pose Model
        interpreterPet = await Interpreter.fromAsset('assets/models/pet_pose_int8.tflite', options: options);
        
        // 2. Object Detection Model
        interpreterObj = await Interpreter.fromAsset('assets/models/yolo11n_int8.tflite', options: options);
        
        // 3. Human Pose Model
        interpreterHuman = await Interpreter.fromAsset('assets/models/yolo11n-pose_int8.tflite', options: options);

        print("Edge Isolate: All 3 Models Loaded");
        initData.sendPort.send({'init_done': true});
        
      } catch (e, stack) {
        print("Edge Isolate Init Error: $e");
        initData.sendPort.send({'init_done': false, 'error': e.toString()});
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
          const int targetW = 1280;
          const int targetH = 1280;
          
          final inputTensor = interpreterPet!.getInputTensor(0);
          
          // [DEBUG] Check Quantization Params
          print("Input Type: ${inputTensor.type}, Params: ${inputTensor.params}");

          // [Optimization] Use Float32 Flat Buffer (Safe Fallback)
          // 1280x1280 Float32 is supported by TFLite (via auto-quantization or float input) and worked previously.
          // We bypass `_prepareInputTensor` to avoid `reshape()` crash.
          final floatInput = convertYUVToFloat32Tensor(rawData, targetW, targetH, rotation);
          
          final outputTensor = interpreterPet!.getOutputTensor(0);
          final outputShape = outputTensor.shape; 
          
          result['debug_info']['shape'] = outputShape.toString();
          result['debug_info']['inputType'] = inputTensor.type.toString();
          
          final outputBuffer = Float32List(outputShape.reduce((a, b) => a * b));
          final outputMap = {0: outputBuffer}; 
          
          // Pass Flat Float32 List directly. TFLite usually handles flat input if size matches.
          interpreterPet!.runForMultipleInputs([floatInput], outputMap);

          final detections = nonMaxSuppression(
            outputBuffer,  
            3, 
            0.15, 0.45,
            keypointNum: 17,
            shape: outputShape 
          );
          
           result['debug_info']['pet_count'] = detections.length;

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
            
            final uint8Input = convertYUVToRGBBytes(rawData, targetW, targetH, rotation);
            
            final outputTensor = interpreterObj!.getOutputTensor(0);
            final shape = outputTensor.shape;
            
            final outputBuffer = Float32List(shape.reduce((a, b) => a * b));
            final outputMap = {0: outputBuffer}; 
            
            interpreterObj!.runForMultipleInputs([uint8Input], outputMap);
  
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
            final uint8Input = convertYUVToRGBBytes(rawData, targetSize, targetSize, rotation);
            
            final outputTensor = interpreterHuman!.getOutputTensor(0);
            final shape = outputTensor.shape;
            final outputBuffer = Float32List(shape.reduce((a, b) => a * b));
            final outputMap = {0: outputBuffer}; // Flat buffer
            
            interpreterHuman!.runForMultipleInputs([uint8Input], outputMap);
            
            final rawOutput = outputMap[0] as List;
            final batch0 = rawOutput[0] as List;
  
            final detections = nonMaxSuppression(
               batch0,
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
        result['error'] = "Inference Error: $e"; // [DEBUG] Propagate error
        result['stack'] = stack.toString();
      }
      
      sw.stop();
      print("Edge Inference took: ${sw.elapsedMilliseconds}ms");
      result['debug_info']['inference_ms'] = sw.elapsedMilliseconds;
      
      initData.sendPort.send(result);
    }
    else if (cmd == Cmd.close) {
      interpreterPet?.close();
      interpreterObj?.close();
      interpreterHuman?.close();
      Isolate.exit();
    }
    else if (cmd == Cmd.ping) {
      initData.sendPort.send({'pong': true});
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

