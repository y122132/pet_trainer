import 'package:image/image.dart' as img;
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as import_math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // compute 함수 사용을 위해 추가
import 'package:provider/provider.dart';
import '../providers/char_provider.dart';
import '../services/socket_client.dart';
import 'my_room_page.dart' as import_my_room_page;
import '../widgets/stat_distribution_dialog.dart';

// --- 최상위 함수 (Top-level function) ---
// 백그라운드 Isolate에서 실행될 함수입니다. compute()는 최상위 함수여야 합니다.
Uint8List processCameraImageToJpeg(Map<String, dynamic> data) {
  final int width = data['width'];
  final int height = data['height'];
  final int sensorOrientation = data['sensorOrientation'] ?? 0;
  final List<dynamic> planes = data['planes'];
  
  // YUV 데이터 추출
  final Uint8List yBytes = planes[0]['bytes'];
  final Uint8List uBytes = planes[1]['bytes'];
  final Uint8List vBytes = planes[2]['bytes'];
  
  final int uvRowStride = planes[1]['bytesPerRow'];
  final int uvPixelStride = planes[1]['bytesPerPixel'] ?? 1;

  final img.Image yuvImage = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int uvIndex = uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
      final int index = y * width + x;
      
      final int yValue = yBytes[index];
      final int uValue = uBytes[uvIndex];
      final int vValue = vBytes[uvIndex];

      int r = (yValue + 1.402 * (vValue - 128)).round();
      int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round();
      int b = (yValue + 1.772 * (uValue - 128)).round();

      yuvImage.setPixelRgba(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255), 255);
    }
  }
  
  // 리사이징 (비율 유지, 가로 640 고정)
  // 강제로 height를 지정하지 않아 원본의 비율(Aspect Ratio)을 유지합니다.
  // 세로 촬영 시 찌그러짐(왜곡) 방지에 필수적입니다.
  img.Image resizedImage = img.copyResize(yuvImage, width: 640);

  // [User Request] 이미지 회전 보정 (스마트폰 카메라는 보통 90도 돌아가 있음)
  if (sensorOrientation != 0) {
    resizedImage = img.copyRotate(resizedImage, angle: sensorOrientation);
  }

  /* 실제 핸드폰용 (고품질) */
  return Uint8List.fromList(img.encodeJpg(resizedImage, quality: 85));
  
  /* 에뮬레이터/테스트용 (품질 상향: 40 -> 70) */
  // return Uint8List.fromList(img.encodeJpg(resizedImage, quality: 70));
}

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
  // [Debug] 디버깅용 변수 (타겟 무관 최고 점수)
  double _maxConfAny = 0.0;
  int _maxConfCls = -1; 
  
  // --- FSM & UI 피드백 변수 ---
  String _trainingState = 'READY'; // READY, DETECTING, STAY, SUCCESS
  double _stayProgress = 0.0;
  String _progressText = '';
  
  // --- 스트리밍 & Flow Control 변수 ---
  bool _isProcessingFrame = false; // 로컬 변환 작업 중복 방지
  bool _canSendFrame = true;       // 서버 응답 대기 (Flow Control)
  int _lastFrameSentTimestamp = 0; // 마지막 전송 시각 (최소 간격용)

  /* 실제 핸드폰 용 */
  static const int _frameInterval = 150;  // 최소 간격 (서버가 빠르면 더 자주 보낼 수 있도록 200ms -> 100ms 단축)
  
  /* 에뮬레이터 테스트용 */
  // static const int _frameInterval = 300; // 최소 간격 (ms)
  
  // --- 디버그 & 시각화 변수 ---
  int _frameStartTime = 0; // 프레임 전송 시작 시간 (Latency 계산용)
  int _latency = 0;        // 왕복 지연 시간 (ms)
  List<dynamic> _bbox = []; // 탐지된 객체 바운딩 박스 [x1, y1, x2, y2]

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
      ResolutionPreset.high, 
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
        _bbox = [];
        _latency = 0;
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
    
    _canSendFrame = true; // 시작 시 전송 허용
    _socketClient.connect(petType, widget.difficulty, widget.mode);
    
    _socketClient.stream.listen((message) {
      if (!mounted) return;
      
      // 서버로부터 응답을 받으면 다음 프레임 전송 허용 (ACK)
      _canSendFrame = true; 
      
      // Latency 계산
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_frameStartTime > 0) {
        _latency = now - _frameStartTime;
      }

      try {
        final data = jsonDecode(message);
        final provider = Provider.of<CharProvider>(context, listen: false);
        final status = data['status'] as String?;

        if (mounted) {
          setState(() {
            _trainingState = status?.toUpperCase() ?? _trainingState;

            if (_trainingState == 'STAY') {
              final msg = data['message'] as String? ?? '';
              final match = RegExp(r'(\d+\.\d+)').firstMatch(msg);
              if (match != null) {
                final remaining = double.tryParse(match.group(1) ?? '3.0') ?? 3.0;
                _stayProgress = (3.0 - remaining) / 3.0;
                _progressText = "${remaining.toStringAsFixed(1)}초 유지 중...";
              }
            } else if (_trainingState != 'SUCCESS') {
              _stayProgress = 0.0;
              _progressText = '';
            }
            
            if (data.containsKey('keypoints')) _keypoints = data['keypoints'];
            if (data.containsKey('bbox')) _bbox = data['bbox'];
            if (data.containsKey('image_width')) _imageWidth = (data['image_width'] as num).toDouble();
            if (data.containsKey('image_height')) _imageHeight = (data['image_height'] as num).toDouble();
            if (data.containsKey('feedback')) _feedback = data['feedback'];
            // [User Request] 신뢰도 점수 업데이트 (서버 키 확인)
            if (data.containsKey('conf_score')) {
              _confScore = (data['conf_score'] as num?)?.toDouble() ?? 0.0;
            }
            // [Debug] 디버그 정보 업데이트
            if (data.containsKey('debug_max_conf')) {
              _maxConfAny = (data['debug_max_conf'] as num?)?.toDouble() ?? 0.0;
            }
            if (data.containsKey('debug_max_cls')) {
              _maxConfCls = (data['debug_max_cls'] as num?)?.toInt() ?? -1;
            }
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
      }
    }, onError: (error) {
      if (mounted) {
        print("소켓 에러: $error");
        Provider.of<CharProvider>(context, listen: false).updateStatusMessage("통신 오류: $error");
        // 에러 발생 시 UI 업데이트 및 전송 락 해제
        setState(() {
            _canSendFrame = true; // 에러 발생 시에도 다시 시도할 수 있도록 허용
        });
      }
    });

    _controller.startImageStream(_processCameraImage);
    provider.updateStatusMessage("분석 시작... 포즈를 취해주세요!");
  }
  
  void _processCameraImage(CameraImage image) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // 1. 최소 간격 체크 (너무 빠른 전송 방지)
    // 2. 로컬 변환 작업 중복 방지 (_isProcessingFrame)
    // 3. 서버 응답 대기 (_canSendFrame) - Flow Control 핵심
    if (now - _lastFrameSentTimestamp <= _frameInterval || _isProcessingFrame || !_canSendFrame) {
      return;
    }

    _isProcessingFrame = true;

    try {
      if (image.format.group == ImageFormatGroup.yuv420) {
        // Isolate로 넘기기 위해 필요한 데이터만 추출 (복사 발생)
        // CameraImage 객체 자체는 Isolate로 넘어갈 수 없음
        final rawData = {
          'width': image.width,
          'height': image.height,
          'sensorOrientation': _controller.description.sensorOrientation,
          'planes': image.planes.map((plane) => {
            'bytes': plane.bytes, // Uint8List
            'bytesPerRow': plane.bytesPerRow,
            'bytesPerPixel': plane.bytesPerPixel,
          }).toList(),
        };

        // compute를 사용하여 백그라운드에서 변환 작업 수행
        final jpegBytes = await compute(processCameraImageToJpeg, rawData);
        
        if (mounted && _isAnalyzing && _canSendFrame) {
          // 전송 직전 시간 기록 및 락 걸기
          _frameStartTime = DateTime.now().millisecondsSinceEpoch;
          _canSendFrame = false;
          _lastFrameSentTimestamp = _frameStartTime;
          
          _socketClient.sendMessage(jpegBytes);
        }
      } 
    } catch (e) {
      print("프레임 처리 실패: $e");
    } finally {
      // 변환 작업 완료 (다음 프레임 변환 준비)
      _isProcessingFrame = false;
    }
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
    bool isFront = widget.cameras.first.lensDirection == CameraLensDirection.front;
    
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
                // Stack: 전체 화면 레이어 (폭죽 효과, FAB 등 오버레이를 위해 필요)
                return Stack(
                  children: [
                    // 메인 레이아웃: 항상 상하 분할 (Column)
                    Column(
                      children: [
                        // [상단 50%] 카메라 프리뷰 영역
                        Expanded(
                          flex: 1,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // 1. 카메라 프리뷰
                              CameraPreview(_controller),
                              
                              // 2. 분석 시각화 레이어 (분석 중일 때만)
                              if (_isAnalyzing) ...[
                                CustomPaint(
                                  painter: DebugBoxPainter(
                                    bbox: _bbox, 
                                    isFrontCamera: isFront,
                                    // [User Request] 좌표 보정을 위한 비율 정보 전달
                                    imgRatio: _controller.value.aspectRatio
                                  )
                                ),
                                if (_imageWidth > 0)
                                  CustomPaint(
                                    painter: PosePainter(
                                      keypoints: _keypoints, 
                                      imageWidth: _imageWidth, 
                                      imageHeight: _imageHeight, 
                                      feedback: _feedback, 
                                      isFrontCamera: isFront,
                                      imgRatio: _controller.value.aspectRatio // 포즈에도 비율 전달
                                    )
                                  ),
                              ],

                              // 3. STAY 카운트다운
                              if (_isAnalyzing && _trainingState == 'STAY')
                                Container(
                                  color: Colors.black.withOpacity(0.3),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(value: _stayProgress, strokeWidth: 8, valueColor: const AlwaysStoppedAnimation<Color>(Colors.lightGreenAccent)),
                                        const SizedBox(height: 10),
                                        Text(_progressText, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
                                      ],
                                    ),
                                  ),
                                ),
                              
                              // 4. 연결 경고
                              if (_isAnalyzing && !_socketClient.isConnected)
                                Container(
                                  color: Colors.black54,
                                  child: const Center(
                                    child: Text("⚠️ 서버 연결 확인 중...", style: TextStyle(color: Colors.redAccent, fontSize: 24, fontWeight: FontWeight.bold)),
                                  ),
                                ),

                              // 5. 디버그 정보 (상단 영역 좌측)
                              if (_isAnalyzing)
                                Positioned(
                                  top: 10, left: 10,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(8)
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Status: $_trainingState", style: const TextStyle(color: Colors.white, fontSize: 10)),
                                        Text("Confidence: ${(_confScore * 100).toStringAsFixed(1)}%", 
                                          style: TextStyle(color: _confScore > 0.5 ? Colors.greenAccent : Colors.redAccent, fontSize: 10)
                                        ),
                                        Text("Latency: ${_latency}ms", style: const TextStyle(color: Colors.white, fontSize: 10)),
                                        // [Debug] 오인식 정보 표시
                                        if (_maxConfAny > 0)
                                          Text("Raw Max: ${(_maxConfAny * 100).toStringAsFixed(1)}% (ID: $_maxConfCls)", 
                                            style: const TextStyle(color: Colors.yellowAccent, fontSize: 10, fontWeight: FontWeight.bold)
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // [하단 50%] 캐릭터 및 메시지 영역
                        Expanded(
                          flex: 1,
                          child: Container(
                            width: double.infinity,
                            color: Colors.white,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // 캐릭터 이미지
                                Expanded(
                                  child: Image.asset(
                                    provider.character?.imageUrl ?? "assets/images/characters/char_default.png",
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                // 메시지 박스
                                Container(
                                  padding: const EdgeInsets.all(15),
                                  margin: const EdgeInsets.only(left: 20, right: 20, bottom: 20, top: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!_isAnalyzing)
                                        const Text("대기 중", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                                      const SizedBox(height: 5),
                                      Text(
                                        provider.statusMessage,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.4),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // [최상단 오버레이] 폭죽 효과
                    if (_particles.isNotEmpty)
                      IgnorePointer(child: CustomPaint(painter: ConfettiPainter(_particles), size: Size.infinite)),
                    
                    // [최상단 오버레이] 컨트롤 버튼 (하단 중앙)
                    Positioned(
                      bottom: 150, left: 0, right: 0,
                      child: Center(
                        child: FloatingActionButton.extended(
                          onPressed: _cameraError == null ? _toggleAnalysis : null,
                          backgroundColor: _isAnalyzing ? Colors.redAccent : Colors.indigo,
                          icon: Icon(_isAnalyzing ? Icons.stop : Icons.play_arrow),
                          label: Text(_isAnalyzing ? "그만하기" : "훈련 시작", style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
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
// YOLO COCO Class ID Map
const Map<int, String> yoloClasses = {
  0: 'Person',
  15: 'Cat',
  16: 'Dog',
  28: 'Handbag', // 가방(장난감대용)
  29: 'Frisbee',
  32: 'Ball',
  39: 'Bottle',
  41: 'Cup',
  45: 'Bowl',
  46: 'Banana',
  47: 'Apple',
  48: 'Sandwich',
  49: 'Orange',
  50: 'Broccoli',
  51: 'Carrot',
  77: 'Teddy',
};

// Bounding Box 시각화 Painter
class DebugBoxPainter extends CustomPainter {
  final List<dynamic> bbox; // [x1, y1, x2, y2] (0.0 ~ 1.0)
  final bool isFrontCamera;
  final double imgRatio; // 카메라 이미지 비율 (width / height) - 보통 3/4 (0.75) 등

  DebugBoxPainter({required this.bbox, required this.isFrontCamera, required this.imgRatio});

  @override
  @override
  void paint(Canvas canvas, Size size) {
    if (bbox.isEmpty) return;

    // 공통 렌더링 파라미터 계산 (프레임 단위 고정값)
    // 1. 화면 비율 계산
    double screenRatio = size.width / size.height;
    
    // 2. 실제 렌더링될 이미지의 스케일과 오프셋 계산
    double renderW, renderH;
    
    // 올바른 접근:
    // 실제 카메라 이미지의 종횡비 사용. (imgRatio가 Portrait 기준 W/H라고 가정)
    // 만약 imgRatio가 4/3(1.33) 처럼 1보다 크면 Landscape임. 뒤집어야 함.
    double effectiveImgRatio = imgRatio;
    if (effectiveImgRatio > 1.0 && size.width < size.height) {
        effectiveImgRatio = 1.0 / effectiveImgRatio; 
    }
    
    if (screenRatio > effectiveImgRatio) {
       // 화면이 더 납작함 -> 폭에 맞춤 (위아래 잘림)
       renderW = size.width;
       renderH = size.width / effectiveImgRatio;
    } else {
       // 화면이 더 길쭉함 -> 높이에 맞춤 (좌우 잘림)
       renderH = size.height;
       renderW = size.height * effectiveImgRatio;
    }
    
    // 오프셋 (센터 크롭 가정)
    double dx = (size.width - renderW) / 2.0;
    double dy = (size.height - renderH) / 2.0;

    // 그리기 도구 설정 (기본값)
    final paintPet = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
      
    final paintProp = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // 단일 박스 포맷 호환성 처리 & 빈 리스트 처리
    List<dynamic> targets = [];
    if (bbox.isNotEmpty) {
        if (bbox[0] is List) {
           targets = bbox;
        } else if (bbox.length >= 4) {
           targets = [bbox]; // 구버전 호환 (단일 박스)
       }
    }

    // 모든 박스 그리기
    for (var box in targets) {
      if (box.length < 4) continue;

      // 정규화된 좌표 (0.0 ~ 1.0)
      double nx1 = (box[0] as num).toDouble();
      double ny1 = (box[1] as num).toDouble();
      double nx2 = (box[2] as num).toDouble();
      double ny2 = (box[3] as num).toDouble();

      // 최종 화면 좌표 변환
      double x1, x2;
      if (isFrontCamera) {
         // 전면카메라는 좌우 반전
         double rx1 = (1.0 - nx2) * renderW + dx;
         double rx2 = (1.0 - nx1) * renderW + dx;
         x1 = rx1; x2 = rx2;
      } else {
         x1 = nx1 * renderW + dx;
         x2 = nx2 * renderW + dx;
      }
      double y1 = ny1 * renderH + dy;
      double y2 = ny2 * renderH + dy;

      final rect = Rect.fromLTRB(x1, y1, x2, y2);
      
      // 박스 그리기 및 정보 준비
      String debugInfo = "";
      Paint currentPaint = paintProp; // 기본은 파란색 (도구)
      
      if (box.length > 5) {
         int cls = (box[5] as num).toInt();
         int conf = ((box[4] as num) * 100).toInt();
         
         // 15:Cat, 16:Dog -> 빨간색
         String name = yoloClasses[cls] ?? "ID:$cls";
         
         if (cls == 15 || cls == 16) {
             currentPaint = paintPet;
             debugInfo = "$name $conf%";
         } else {
             // 그 외 (장난감, 식기 등) -> 파란색
             currentPaint = paintProp;
             debugInfo = "$name $conf%";
         }
      }
      
      canvas.drawRect(rect, currentPaint);
      
      final textPainter = TextPainter(
        text: TextSpan(
          text: debugInfo, 
          style: TextStyle(
            color: currentPaint.color, // 박스 색과 동일하게
            fontSize: 14, 
            fontWeight: FontWeight.bold, 
            backgroundColor: Colors.black54
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x1, y1 - 20)); // 박스 바로 위에 표시
    }
  }

  @override
  bool shouldRepaint(covariant DebugBoxPainter oldDelegate) {
    return oldDelegate.bbox != bbox || oldDelegate.imgRatio != imgRatio;
  }
}

// 사람 스켈레톤 그리기 (교감 모드용)
class PosePainter extends CustomPainter {
  final List<dynamic> keypoints;
  final double imageWidth; 
  final double imageHeight;
  final String feedback;
  final bool isFrontCamera;
  final double imgRatio; // [New]

  PosePainter({
    required this.keypoints,
    required this.imageWidth,
    required this.imageHeight,
    required this.feedback,
    required this.isFrontCamera,
    required this.imgRatio, // [New]
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (keypoints.isEmpty) return;

    final Color color = feedback.isEmpty || feedback == "no_action" ? Colors.redAccent : Colors.greenAccent;
    
    final paint = Paint() //
      ..color = color
      ..strokeWidth = 3.0 
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0;

    // --- 좌표 보정 로직 (DebugBoxPainter와 동일) ---
    double screenRatio = size.width / size.height;
    double effectiveImgRatio = imgRatio;
    if (effectiveImgRatio > 1.0 && size.width < size.height) {
        effectiveImgRatio = 1.0 / effectiveImgRatio; 
    }
    
    double renderW, renderH;
    if (screenRatio > effectiveImgRatio) {
       renderW = size.width;
       renderH = size.width / effectiveImgRatio;
    } else {
       renderH = size.height;
       renderW = size.height * effectiveImgRatio;
    }
    
    double dx = (size.width - renderW) / 2.0;
    double dy = (size.height - renderH) / 2.0;

    List<Offset> points = [];

    for (var kp in keypoints) {
      if (kp is List && kp.length >= 2) {
        double normX = (kp[0] as num).toDouble();
        double normY = (kp[1] as num).toDouble();
        
        // 보정된 좌표 변환
        double finalX;
        if (isFrontCamera) {
             finalX = (1.0 - normX) * renderW + dx;
        } else {
             finalX = normX * renderW + dx;
        }
        double finalY = normY * renderH + dy;
        
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
    return oldDelegate.keypoints != keypoints || oldDelegate.feedback != feedback || oldDelegate.imgRatio != imgRatio;
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