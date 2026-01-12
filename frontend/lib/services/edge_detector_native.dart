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
    // 1. If Isolate exists, check Health (Self-Healing)
    if (_isolate != null && _sendPort != null) {
       bool isHealthy = await _checkHealth();
       if (isHealthy) return; // All good
       
       print("Edge AI Isolate Unhealthy! Restarting...");
       // Kill and Restart
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
          _initCompleter?.complete();
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
    _requests.clear();
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

    return completer.future;

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
        if (Platform.isAndroid) options.addDelegate(XNNPackDelegate());
        
        // 1. Pet Pose Model (1280px)
        interpreterPet = await Interpreter.fromAsset('assets/models/pet_pose_int8.tflite', options: options);
        
        // 2. Object Detection Model (640px)
        interpreterObj = await Interpreter.fromAsset('assets/models/yolo11n_int8.tflite', options: options);
        
        // 3. Human Pose Model (640px)
        interpreterHuman = await Interpreter.fromAsset('assets/models/yolo11n-pose_int8.tflite', options: options);

        print("Edge Isolate: All 3 Models Loaded");
        
        initData.sendPort.send({'init_done': true});
      } catch (e) {
        print("Edge Isolate Init Error: $e");
      }
    } 
    else if (cmd == Cmd.detect) {
      final id = message['req_id'];
      final rawData = message['data'];
      final mode = message['mode'];
      final rotation = message['rotation'] ?? 0;
      
      final result = <String, dynamic>{
        'req_id': id,
        'success': false,
        'bbox': [], // Final merged list
        'conf_score': 0.0
      };
      
      if (interpreterPet == null) {
        initData.sendPort.send(result);
        return;
      }

      try {
        final List<List<dynamic>> allDetections = [];
        double maxConf = 0.0;

        // --- Model A: Pet Pose (Always Run, 1280px) ---
        try {
          const targetSize = 1280;
          final floatInput = convertYUVToFloat32Tensor(rawData, targetSize, targetSize, rotation);
          
          final inputTensor = interpreterPet!.getInputTensor(0);
          final input = _prepareInputTensor(floatInput, inputTensor);
          
          final outputTensor = interpreterPet!.getOutputTensor(0);
          final shape = outputTensor.shape; 
          final outputBuffer = Float32List(shape.reduce((a, b) => a * b));
          final outputMap = {0: outputBuffer.reshape(shape)};
          
          interpreterPet!.runForMultipleInputs([input], outputMap);
          
          final rawOutput = outputMap[0] as List;
          final batch0 = rawOutput[0] as List;

          final detections = nonMaxSuppression(
            batch0, 
            3, // Pet Classes: Dog(0->16), Cat(1->15), Bird(2->14)
            0.30, 0.45
          );
          
          for (var det in detections) {
             int mappedCls = 16; // Default Dog
             if (det.classIndex == 1) mappedCls = 15; // Cat
             if (det.classIndex == 2) mappedCls = 14; // Bird
             
             // [Fix] Normalize Coordinates (0.0 ~ 1.0)
             allDetections.add([
               det.box[0] / targetSize, det.box[1] / targetSize, det.box[2] / targetSize, det.box[3] / targetSize,
               det.score,
               mappedCls.toDouble()
             ]);
             if (det.score > maxConf) maxConf = det.score;
          }
        } catch (e) {
             print("Model A (Pet) Failed: $e");
        }

        // --- Model B: Object Detection (Run if NOT interaction, 640px) ---
        if (mode != 'interaction' && interpreterObj != null) {
          try {
            const targetSize = 640;
            final floatInput = convertYUVToFloat32Tensor(rawData, targetSize, targetSize, rotation);
            final input = floatInput.reshape([1, targetSize, targetSize, 3]);
            
            final outputTensor = interpreterObj!.getOutputTensor(0);
            final shape = outputTensor.shape;
            final outputBuffer = Float32List(shape.reduce((a, b) => a * b));
            final outputMap = {0: outputBuffer.reshape(shape)};
            
            interpreterObj!.runForMultipleInputs([input], outputMap);
            
            final rawOutput = outputMap[0] as List;
            final batch0 = rawOutput[0] as List;
  
            final detections = nonMaxSuppression(
               batch0,
               80, // COCO Classes
               0.25, 0.45 
            );
            
            for (var det in detections) {
               // Use original COCO class index
               allDetections.add([
                 det.box[0] / targetSize, det.box[1] / targetSize, det.box[2] / targetSize, det.box[3] / targetSize,
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
            final floatInput = convertYUVToFloat32Tensor(rawData, targetSize, targetSize, rotation);
            final input = floatInput.reshape([1, targetSize, targetSize, 3]);
            
            final outputTensor = interpreterHuman!.getOutputTensor(0);
            final shape = outputTensor.shape;
            final outputBuffer = Float32List(shape.reduce((a, b) => a * b));
            final outputMap = {0: outputBuffer.reshape(shape)};
            
            interpreterHuman!.runForMultipleInputs([input], outputMap);
            
            final rawOutput = outputMap[0] as List;
            final batch0 = rawOutput[0] as List;
  
            final detections = nonMaxSuppression(
               batch0,
               1, // Person Class
               0.30, 0.45
            );
            
            for (var det in detections) {
               // Person class is 0. Map to 0.
               allDetections.add([
                 det.box[0] / targetSize, det.box[1] / targetSize, det.box[2] / targetSize, det.box[3] / targetSize,
                 det.score,
                 0.0 // Person
               ]);
            }
          } catch (e) {
            print("Model C (Human) Failed: $e");
          }
        }

        
        if (allDetections.isNotEmpty) {
           result['success'] = true;
           result['bbox'] = allDetections;
           result['conf_score'] = maxConf;
           
           // TODO: Implement Logic (Distance/Interaction) Here
           // For now, we just pass detections to Server (via socket)
           // But since Server is Bypassed, logic MUST be here.
           // However, implementing full logic is Step 3-2.
           // We will currently just return BBox so UI works, 
           // but Game Logic (FSM) will likely FAIL or IDLE because result['success'] might be misused?
           // Wait, Server side 'detector.py' logic does FSM.
           // Edge Mode sends 'result' JSON. Server uses 'result' for FSM.
           // BUT Server FSM relies on 'vision_state' and detection history inside Server memory.
           // So if we just send BBox, Server FSM logic in 'analysis_socket.py' checks 'is_success_vision'.
           // Ideally we need to run 'logic' here to determine 'is_success_vision' accurately (e.g. distance check).
           // Currently we set 'success' = true if ANY detection found. This is temporary.
           // We need Step 3 logic porting soon.
        }

      } catch (e) {
        print("Edge Inference Error: $e");
      }
      
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
    
    final size = floatInput.length;
    final uint8 = Uint8List(size);
    for (int i = 0; i < size; i++) {
       // float = (q - zp) * scale
       // q = float / scale + zp
       uint8[i] = (floatInput[i] / scale + zeroPoint).round().clamp(0, 255);
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

