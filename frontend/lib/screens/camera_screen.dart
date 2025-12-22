import 'package:image/image.dart' as img;
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as import_math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/char_provider.dart';
import '../services/socket_client.dart';
import 'my_room_page.dart' as import_my_room_page;
import '../widgets/stat_distribution_dialog.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final String difficulty; // 'easy' 또는 'hard'
  final String mode; // 'playing', 'feeding', 'interaction' 등

  const CameraScreen({super.key, required this.cameras, this.mode = 'exercise', this.difficulty = 'easy'});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with TickerProviderStateMixin {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  final SocketClient _socketClient = SocketClient();
  
  // --- 상태 변수 (State Variables) ---
  bool _isAnalyzing = false; // 현재 AI 분석이 진행 중인지 여부
  String? _cameraError;
  String _feedback = ""; // AI가 보내준 실시간 피드백 메시지 (예: "더 가까이")
  double _confScore = 0.0; // 인식 신뢰도 점수 (0.0 ~ 1.0)
  
  // --- FSM & UI 피드백 변수 ---
  String _trainingState = 'READY'; // READY, DETECTING, STAY, SUCCESS
  double _stayProgress = 0.0;
  String _progressText = '';
  
  // --- 스트리밍 & 쓰로틀링 (Streaming & Throttling) ---
  bool _isProcessingFrame = false; // 프레임 처리 중복 방지
  int _lastFrameSentTimestamp = 0; // 마지막으로 프레임을 보낸 시간
  static const int _frameInterval = 200; // 프레임 전송 간격 (ms)

  // --- 시각화 데이터 (Visualization Data) ---
  List<dynamic> _keypoints = []; // 사람 스켈레톤 좌표 (교감 모드용)
  double _imageWidth = 0; // 분석된 이미지 원본 너비 (좌표 변환용)
  double _imageHeight = 0; // 분석된 이미지 원본 높이

  // --- 애니메이션 (Animation) ---
  late AnimationController _confettiController; // 성공 시 폭죽 효과 제어
  List<ConfettiParticle> _particles = [];
  
  @override
  void initState() {
    super.initState();
    // 카메라 초기화: 성능을 위해 해상도는 Medium으로 설정 (분석용으로 충분함)
    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.medium, 
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420, // 스트리밍을 위해 포맷 지정
    );
    
    _initializeControllerFuture = _controller.initialize().catchError((e) {
      if (!mounted) return;
      print("Camera init error: $e");
      setState(() {
        _cameraError = e.toString();
      });
    });

    // 컨페티 애니메이션 컨트롤러 초기화
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..addListener(() {
      if (mounted) {
        setState(() {
          for (var p in _particles) {
            p.update();
          }
        });
      }
    });
    
    // 화면 진입 시 캐릭터 최신 정보 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<CharProvider>(context, listen: false).fetchCharacter();
      }
    });
  }

  // 성공 축하 효과 시작 (폭죽 터뜨리기)
  void _startConfetti() {
    setState(() {
      _particles = List.generate(50, (index) => ConfettiParticle());
    });
    _confettiController.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    _socketClient.disconnect(); // 화면 종료 시 소켓 연결 해제
    _confettiController.dispose();
    super.dispose();
  }

  // [핵심 로직] 분석 시작/중지 토글
  void _toggleAnalysis() {
    if (!mounted) return;

    setState(() {
      _isAnalyzing = !_isAnalyzing;
      // 중지 시 데이터 초기화 (잔상 제거)
      if (!_isAnalyzing) {
        _keypoints = [];
        _feedback = "";
        _trainingState = 'READY';
        _stayProgress = 0.0;
        _progressText = '';
        _stopAnalysis(); // 스트림 중지 및 소켓 연결 해제
      } else {
        // 분석 시작
        _startAnalysis();
      }
    });
  }
  
  void _startAnalysis() {
    if (!mounted) return;
    final provider = Provider.of<CharProvider>(context, listen: false);
    String petType = provider.currentPetType; 
    
    _socketClient.connect(petType, widget.difficulty, widget.mode);
    
    _socketClient.stream.listen((message) {
      if (!mounted) return;
      
      try {
        final data = jsonDecode(message);
        final provider = Provider.of<CharProvider>(context, listen: false);
        final status = data['status'] as String?;

        if (mounted) {
          setState(() {
            _trainingState = status ?? _trainingState;

            if (_trainingState == 'stay') {
              final message = data['message'] as String? ?? '';
              final match = RegExp(r'(\d+\.\d+)').firstMatch(message);
              if (match != null) {
                final remaining = double.tryParse(match.group(1) ?? '3.0') ?? 3.0;
                _stayProgress = (3.0 - remaining) / 3.0;
                _progressText = "${remaining.toStringAsFixed(1)}초";
              }
            } else if (_trainingState != 'success') {
              _stayProgress = 0.0;
              _progressText = '';
            }
            
            if (data.containsKey('keypoints')) _keypoints = data['keypoints'];
            if (data.containsKey('image_width')) _imageWidth = (data['image_width'] as num).toDouble();
            if (data.containsKey('image_height')) _imageHeight = (data['image_height'] as num).toDouble();
            if (data.containsKey('feedback')) _feedback = data['feedback'];
            if (data.containsKey('conf_score')) _confScore = (data['conf_score'] as num).toDouble();
          });
        }
        
        if (status == 'success') {
           if (data.containsKey('base_reward') && data['base_reward'] is Map) {
              final baseReward = data['base_reward'];
              final bonus = data['bonus_points'] ?? 0;
              
              provider.gainReward(baseReward, bonus);
              _toggleAnalysis();
              _startConfetti();
              _showSuccessDialog(baseReward, bonus);
           }
        }

        if (data.containsKey('message')) {
          String msg = data['message'];
          if (_feedback.isNotEmpty && status != 'success') {
            msg += "\n💡 $_feedback";
          }
          provider.updateStatusMessage(msg);
        }

      } catch (e) {
        print("JSON 파싱 에러: $e");
      } finally {
        _isProcessingFrame = false; 
      }
    }, onError: (error) {
      if (mounted) {
        print("소켓 에러: $error");
        Provider.of<CharProvider>(context, listen: false).updateStatusMessage("통신 오류: $error");
        _isProcessingFrame = false;
      }
    });

    _controller.startImageStream(_processCameraImage);
    provider.updateStatusMessage("분석 시작... 포즈를 취해주세요!");
  }
  
  void _processCameraImage(CameraImage image) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFrameSentTimestamp > _frameInterval && !_isProcessingFrame) {
      _isProcessingFrame = true;
      _lastFrameSentTimestamp = now;

      try {
        if (image.format.group == ImageFormatGroup.yuv420) {
          final jpegBytes = _convertYUV420toJPEG(image);
          _socketClient.sendMessage(base64Encode(jpegBytes));
        } else {
          _isProcessingFrame = false; 
        }
      } catch (e) {
        print("프레임 처리 실패: $e");
        _isProcessingFrame = false;
      }
    }
  }
  
  Uint8List _convertYUV420toJPEG(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final img.Image yuvImage = img.Image(width: width, height: height);
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel!;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex = uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
        final int index = y * width + x;
        final int yValue = image.planes[0].bytes[index];
        final int uValue = image.planes[1].bytes[uvIndex];
        final int vValue = image.planes[2].bytes[uvIndex];
        int r = (yValue + 1.402 * (vValue - 128)).round();
        int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round();
        int b = (yValue + 1.772 * (uValue - 128)).round();
        yuvImage.setPixelRgba(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255), 255);
      }
    }
    
    final img.Image resizedImage = img.copyResize(yuvImage, width: 640, height: 640);
    return Uint8List.fromList(img.encodeJpg(resizedImage, quality: 75));
  }

  void _stopAnalysis() {
    if (_controller.value.isStreamingImages) {
      _controller.stopImageStream();
    }
    _socketClient.disconnect();
    if (mounted) {
       setState(() {
         _isAnalyzing = false;
         _feedback = "";
       });
       Provider.of<CharProvider>(context, listen: false).updateStatusMessage("분석 중지됨.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          widget.mode == 'feeding' ? '🥣 식사' : 
          widget.mode == 'playing' ? '🎾 놀이' : 
          widget.mode == 'interaction' ? '🤝 교감' : '훈련장', 
          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Consumer<CharProvider>(
              builder: (context, provider, child) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Center(
                              child: Image.asset(
                                provider.character?.imageUrl ?? "assets/images/characters/char_default.png",
                                fit: BoxFit.contain,
                                width: size.width * 0.8, 
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.grey.shade300, width: 2),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isAnalyzing ? "분석 중..." : "대기 중",
                                    style: TextStyle(color: _isAnalyzing ? Colors.blueAccent : Colors.grey, fontWeight: FontWeight.bold, fontSize: 14)
                                  ),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      child: Text(
                                        provider.statusMessage,
                                        style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.5),
                                      ),
                                    ),
                                  ),
                                  if (_feedback.isNotEmpty && !_feedback.contains("성공"))
                                    Container(
                                      margin: const EdgeInsets.only(top: 10),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.orange.shade200),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                                          const SizedBox(width: 5),
                                          Text(_feedback, style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: Container(
                        width: 120,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: _controller.value.aspectRatio,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CameraPreview(_controller),
                                if (_isAnalyzing && _imageWidth > 0)
                                  CustomPaint(
                                    painter: PosePainter(keypoints: _keypoints, imageWidth: _imageWidth, imageHeight: _imageHeight, feedback: _feedback),
                                  ),
                                if (_isAnalyzing)
                                  Positioned(
                                    top: 5, right: 5,
                                    child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                                  ),
                                if (_isAnalyzing && _confScore > 0)
                                  Positioned(
                                    top: 5, left: 5,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(4)),
                                      child: Text(
                                        "${(_confScore * 100).toInt()}%",
                                        style: TextStyle(color: _confScore >= 0.55 ? Colors.greenAccent : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_trainingState == 'STAY')
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.4),
                          child: Center(
                            child: SizedBox(
                              width: 160,
                              height: 160,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CircularProgressIndicator(
                                    value: _stayProgress,
                                    strokeWidth: 12,
                                    backgroundColor: Colors.white.withOpacity(0.3),
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.lightGreenAccent),
                                  ),
                                  Center(
                                    child: Text(
                                      _progressText,
                                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_particles.isNotEmpty)
                      IgnorePointer(
                        child: CustomPaint(painter: ConfettiPainter(_particles), size: Size.infinite),
                      ),
                    Positioned(
                      bottom: 20,
                      left: 20,
                      child: FloatingActionButton.extended(
                        onPressed: _cameraError == null ? _toggleAnalysis : null,
                        backgroundColor: _isAnalyzing ? Colors.redAccent : Colors.indigo,
                        icon: Icon(_isAnalyzing ? Icons.stop : Icons.play_arrow),
                        label: Text(_isAnalyzing ? "그만하기" : "훈련 시작", style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                );
              },
            );
          } else if (snapshot.hasError) {
             return Center(child: Text("카메라 오류: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }

  // 성공 팝업 표시
  void _showSuccessDialog(Map<String, dynamic> baseReward, int bonus) {
    if (!mounted) return;
    
    final provider = Provider.of<CharProvider>(context, listen: false);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final currentStats = {
          "strength": provider.character?.stat?.strength ?? 0,
          "intelligence": provider.character?.stat?.intelligence ?? 0,
          "stamina": provider.character?.stat?.stamina ?? 0,
          "happiness": provider.character?.stat?.happiness ?? 0,
          "health": provider.character?.stat?.health ?? 0,
        };

        return StatDistributionDialog(
          availablePoints: provider.unusedStatPoints,
          currentStats: currentStats,
          title: "🎉 훈련 성공!",
          confirmLabel: "마이룸으로 이동",
          skipLabel: "나중에 하기 (Skip)",
          earnedReward: baseReward,
          earnedBonus: bonus,
          onConfirm: (allocated, remaining) {
             if (allocated['strength']! > 0) _applyAllocated('strength', allocated['strength']!, provider);
             if (allocated['intelligence']! > 0) _applyAllocated('intelligence', allocated['intelligence']!, provider);
             if (allocated['stamina']! > 0) _applyAllocated('stamina', allocated['stamina']!, provider);
             if (allocated['happiness']! > 0) _applyAllocated('happiness', allocated['happiness']!, provider);
             if (allocated['health']! > 0) _applyAllocated('health', allocated['health']!, provider);
             _goToMyRoom();
          },
          onSkip: () {
             _goToMyRoom();
          },
        );
      },
    );
  }
  
  void _applyAllocated(String type, int amount, CharProvider provider) {
    for (int i=0; i<amount; i++) {
      provider.allocateStatSpecific(type);
    }
  }

  void _goToMyRoom() {
    if (!mounted) return;
    Navigator.of(context).pop(); 
    Navigator.of(context).pop(); 
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const import_my_room_page.MyRoomPage()), 
    );
  }
}

// --- 헬퍼 클래스 ---

// 사람 스켈레톤 그리기 (교감 모드용)
class PosePainter extends CustomPainter {
  final List<dynamic> keypoints;
  final double imageWidth; 
  final double imageHeight;
  final String feedback;

  PosePainter({
    required this.keypoints,
    required this.imageWidth,
    required this.imageHeight,
    required this.feedback,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (keypoints.isEmpty) return;

    final Color color = feedback.isEmpty || feedback == "no_action" ? Colors.redAccent : Colors.greenAccent;
    
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.0 
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0;

    List<Offset> points = [];

    for (var kp in keypoints) {
      if (kp is List && kp.length >= 2) {
        double normX = (kp[0] as num).toDouble();
        double normY = (kp[1] as num).toDouble();
        double finalX = (1.0 - normX) * size.width;
        double finalY = normY * size.height;
        points.add(Offset(finalX, finalY));
      }
    }

    final connections = [
      [11, 13], [13, 15], [12, 14], [14, 16], [11, 12], [5, 6], [5, 11], [6, 12], 
      [5, 7], [7, 9], [6, 8], [8, 10],
    ];

    for (var conn in connections) {
      if (conn[0] < points.length && conn[1] < points.length) {
        canvas.drawLine(points[conn[0]], points[conn[1]], linePaint);
      }
    }
    
    for (var point in points) {
      canvas.drawCircle(point, 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.keypoints != keypoints || oldDelegate.feedback != feedback;
  }
}

class ConfettiPainter extends CustomPainter {
  final List<ConfettiParticle> particles;
  ConfettiPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (var p in particles) {
      final paint = Paint()..color = p.color;
      canvas.drawCircle(Offset(p.x * size.width, p.y * size.height), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ConfettiPainter oldDelegate) => true;
}

class ConfettiParticle {
  double x = 0.5, y = 0.5, vx = 0, vy = 0, size = 5;
  Color color = Colors.red;
  
  ConfettiParticle() {
    import_math.Random r = import_math.Random();
    x = 0.5;
    y = 0.4;
    vx = (r.nextDouble() - 0.5) * 0.05;
    vy = (r.nextDouble() - 0.5) * 0.05 - 0.02;
    size = r.nextDouble() * 5 + 3;
    color = Color.fromARGB(255, r.nextInt(255), r.nextInt(255), r.nextInt(255));
  }
  
  void update() {
    x += vx;
    y += vy;
    vy += 0.002;
  }
}
