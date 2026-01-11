import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:pet_trainer_frontend/services/edge_utils.dart';

// --- Commands ---
enum Cmd { init, detect, close }

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

  bool get isLoaded => _sendPort != null;

  Future<void> initialize() async {
    if (_isolate != null) return;
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
        } else if (message.containsKey('req_id')) {
          final id = message['req_id'];
          final completer = _requests.remove(id);
          completer?.complete(message);
        }
      }
    });

    return _initCompleter!.future;
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

  void close() {
    _sendPort?.send({'cmd': Cmd.close});
    _isolate?.kill();
    _isolate = null;
    _sendPort = null;
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
  BackgroundIsolateBinaryMessenger.ensureInitialized(initData.rootToken);
  
  final receivePort = ReceivePort();
  initData.sendPort.send(receivePort.sendPort);

  Interpreter? interpreterPet;
  // Interpreter? interpreterObj; // Future expansion
  
  // Buffers
  // Re-use buffers if possible to reduce GC, but for simplicity allocate per frame first

  receivePort.listen((message) async {
    final cmd = message['cmd'] as Cmd;
    
    if (cmd == Cmd.init) {
      try {
        final options = InterpreterOptions();
        if (Platform.isAndroid) options.addDelegate(XNNPackDelegate());
        
        // Load Models (Assume assets exist)
        interpreterPet = await Interpreter.fromAsset('assets/models/pet_pose_int8.tflite', options: options);

        print("Edge Isolate: Models Loaded");
        
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
        'success': false
      };
      
      if (interpreterPet == null) {
        initData.sendPort.send(result);
        return;
      }

      try {
        // 1. Preprocess (YUV -> Float32 [1, 1280, 1280, 3] with Rotation)
        const targetSize = 1280;
        final floatInput = convertYUVToFloat32Tensor(rawData, targetSize, targetSize, rotation);

        
        // Input Tensor: [1, 1280, 1280, 3] -> Flat: [1280*1280*3]
        // Reshape if needed
        final input = floatInput.reshape([1, targetSize, targetSize, 3]);
        
        // Output Tensor: [1, 4+cls, 8400] (YOLOv8 default)
        // Check output shape
        final outputTensor = interpreterPet!.getOutputTensor(0);
        final shape = outputTensor.shape; // e.g. [1, 7, 8400]
        
        // Prepare Output Buffer
        // We use Map to handle multi-output if needed, or just specific tensor
        // Flatten output for easy handling
        final outputBuffer = Float32List(shape.reduce((a, b) => a * b));
        final outputMap = {0: outputBuffer.reshape(shape)};
        
        // 2. Inference
        interpreterPet!.runForMultipleInputs([input], outputMap);
        
        // 3. Post-Process (NMS)
        // Extract raw list
        final rawOutput = outputMap[0] as List; // [1, features, anchors] or similar
        // Need to pass to NMS
        // NMS Logic expects List<List> or flattened access
        // Assuming rawOutput is [Batch, Features, Anchors]
        // rawOutput[0] is [Features][Anchors] nested list likely
        
        final batch0 = rawOutput[0] as List; // Should be List<List<double>> or similar if reshaped?
        // Actually tflite_flutter reshape does create nested lists.
        
        final detections = nonMaxSuppression(
          batch0, 
          3, // Pet Classes (Dog, Cat, Bird)
          0.30, // Conf
          0.45 // IoU
        );
        
        if (detections.isNotEmpty) {
           final best = detections.first;
           result['success'] = true;
           // Format result expected by TrainingController (Mapped to Server format)
           // e.g. 'bbox': [[x1, y1, x2, y2, conf, cls]] (Server format)
           
           // Class Mapping: 0->16(Dog), 1->15(Cat), 2->14(Bird)
           int mappedCls = 16;
           if (best.classIndex == 1) mappedCls = 15;
           if (best.classIndex == 2) mappedCls = 14;
           
           result['bbox'] = [[
             best.box[0], best.box[1], best.box[2], best.box[3],
             best.score,
             mappedCls.toDouble()
           ]];
           result['conf_score'] = best.score;
           
           // TODO: Implement Logic (Distance)
           // If successful interaction, add 'action_type', 'base_reward'
        }

      } catch (e) {
        print("Edge Inference Error: $e");
      }
      
      initData.sendPort.send(result);
    }
    else if (cmd == Cmd.close) {
      interpreterPet?.close();
      Isolate.exit();
    }
  });
}
