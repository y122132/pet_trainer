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
import 'package:fl_chart/fl_chart.dart';
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
  
  // 상태 변수
  bool _isAnalyzing = false; // 분석 중 여부
  bool _isProcessing = false; // 이미지 전송 중 중복 방지
  Timer? _analysisTimer;
  String? _cameraError;
  String _feedback = ""; // AI 피드백 메시지
  double _confScore = 0.0; // 인식 신뢰도 점수
  
  // 스켈레톤 데이터 (교감 모드 시 사람 시각화용)
  List<dynamic> _keypoints = [];
  double _imageWidth = 0;
  double _imageHeight = 0;

  // 애니메이션 (컨페티 효과)
  late AnimationController _confettiController;
  List<ConfettiParticle> _particles = [];
  
  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.medium, // PIP 화면이 작으므로 medium 정도면 충분
      enableAudio: false,
    );
    
    _initializeControllerFuture = _controller.initialize().catchError((e) {
      print("Camera init error: $e");
      if (mounted) {
        setState(() {
          _cameraError = e.toString();
        });
      }
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
    
    // 캐릭터 초기 데이터 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CharProvider>(context, listen: false).fetchCharacter(); // 파라미터 제거 (기본값 사용)
    });
  }

  // 성공 축하 효과 시작
  void _startConfetti() {
    setState(() {
      _particles = List.generate(50, (index) => ConfettiParticle());
    });
    _confettiController.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    _socketClient.disconnect();
    _analysisTimer?.cancel();
    _confettiController.dispose();
    super.dispose();
  }

  // 분석 시작/중지 토글
  void _toggleAnalysis() {
    setState(() {
      _isAnalyzing = !_isAnalyzing;
      // 중지 시 데이터 초기화
      if (!_isAnalyzing) {
        _keypoints = [];
        _feedback = "";
      }
    });

    if (_isAnalyzing) {
      final provider = Provider.of<CharProvider>(context, listen: false);
      String petType = provider.currentPetType; 
      
      // 소켓 연결
      _socketClient.connect(petType, widget.difficulty);
      
      // 메시지 수신 리스너 설정
      _socketClient.stream.listen((message) {
        if (!mounted) return;
        
        try {
          final data = jsonDecode(message);
          final provider = Provider.of<CharProvider>(context, listen: false);

          setState(() {
             // 1. 키포인트(Keypoints) 파싱
             if (data.containsKey('skeleton_points')) {
               _keypoints = data['skeleton_points'];
             } else if (data.containsKey('keypoints')) {
               _keypoints = data['keypoints'];
             } else {
               // 중요: 서버에서 데이터가 없으면 키포인트를 초기화해야 잔상이 남지 않음
               _keypoints = [];
             }

             if (data.containsKey('image_width')) {
               _imageWidth = (data['image_width'] as num).toDouble();
             }
             if (data.containsKey('image_height')) {
               _imageHeight = (data['image_height'] as num).toDouble();
             }
             
             // 2. 피드백 메시지 파싱
             if (data.containsKey('feedback')) {
               _feedback = data['feedback'];
             } else {
               _feedback = "";
             }
             
             // 3. 점수(Conf Score) 파싱
             if (data.containsKey('conf_score')) {
               _confScore = (data['conf_score'] as num).toDouble();
             } else {
               _confScore = 0.0;
             }
          });
          
          // 키포인트 및 해상도 업데이트 (항상 수행)
          if (data['image_width'] != null) _imageWidth = (data['image_width'] as num).toDouble();
          if (data['image_height'] != null) _imageHeight = (data['image_height'] as num).toDouble();
          
          if (data['keypoints'] != null) {
            _keypoints = List<dynamic>.from(data['keypoints']);
          } else {
            _keypoints = [];
          }

          // 4. 성공 상태 확인 (Success Check)
          if (data['status'] == 'success') {
             if (data.containsKey('base_reward') && data['base_reward'] is Map) {
                final baseReward = data['base_reward'];
                final bonus = data['bonus_points'] ?? 0;
                
                // 스탯 업데이트 (Provider 호출)
                provider.gainReward(baseReward, bonus);
                
                // 분석 중지 (훈련 종료)
                _stopAnalysis();
                
                // 시각 효과 (컨페티) 시작
                _startConfetti();
                
                // 성공 대화상자 표시 (스탯 분배 등)
                _showSuccessDialog(baseReward, bonus);
             }
          }
          
          // 화면 갱신 트리거
          setState(() {
             _isAnalyzing = true; 
          });

          // 상태 메시지 업데이트 (성공 또는 실패 피드백 표시)
          if (data.containsKey('message')) {
            String msg = data['message'];
            if (_feedback.isNotEmpty) {
              msg += "\n💡 $_feedback";
            }
            provider.updateStatusMessage(msg);
          }
        } catch (e) {
          print("JSON 파싱 에러: $e");
        }
      }, onError: (error) {
        print("소켓 에러: $error");
        if (mounted) {
           Provider.of<CharProvider>(context, listen: false).updateStatusMessage("통신 오류: $error");
        }
      });

      // 프레임 캡처 루프 (200ms 간격)
      _analysisTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
        if (_controller.value.isInitialized && !_isProcessing && _isAnalyzing) {
            _isProcessing = true;
            try {
              final image = await _controller.takePicture();
              final bytes = await image.readAsBytes();
              // print("DEBUG: 프레임 전송 (${bytes.length} bytes)...");
              _socketClient.sendMessage(base64Encode(bytes)); // 수정: base64Encode 필요 (SocketClient 수정에 따름)
            } catch (e) {
              print("프레임 캡처 실패: $e");
            } finally {
              _isProcessing = false;
            }
        }
      });
      
      Provider.of<CharProvider>(context, listen: false).updateStatusMessage("분석 시작... 포즈를 취해주세요!");

    } else {
      _stopAnalysis();
    }
  }

  void _stopAnalysis() {
    _socketClient.disconnect();
    _analysisTimer?.cancel();
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
      backgroundColor: const Color(0xFFF5F5F5), // 부드러운 회색 배경
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
                    // --- 1. 메인 배경 & 캐릭터 ("방" 화면) ---
                    Positioned.fill(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 캐릭터 이미지 (크게)
                          Expanded(
                            flex: 3,
                            child: Center(
                              child: Image.asset(
                                provider.character?.imageUrl ?? "assets/images/characters/char_default.png", // 안전한 접근
                                fit: BoxFit.contain,
                                width: size.width * 0.8, 
                              ),
                            ),
                          ),
                          
                          // 대화창 / 상태 박스
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
                                    _isAnalyzing 
                                      ? "분석 중..." 
                                      : "대기 중",
                                    style: TextStyle(
                                      color: _isAnalyzing ? Colors.blueAccent : Colors.grey,
                                      fontWeight: FontWeight.bold, 
                                      fontSize: 14
                                    )
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
                                  // 즉각적인 피드백 (경고/안내)
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
                          const SizedBox(height: 100), // 하단 컨트롤 공간 확보
                        ],
                      ),
                    ),

                    // --- 2. PIP 카메라 미리보기 (우측 하단) ---
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: Container(
                        width: 120,
                        // 높이는 AspectRatio에 의해 자동 결정
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
                                // 카메라 영상
                                CameraPreview(_controller),
                                
                                // 스켈레톤 오버레이 (교감 모드에서 사람 뼈대 그리기)
                                if (_isAnalyzing && _imageWidth > 0)
                                  CustomPaint(
                                    painter: PosePainter(
                                      keypoints: _keypoints,
                                      imageWidth: _imageWidth,
                                      imageHeight: _imageHeight,
                                      feedback: _feedback,
                                    ),
                                  ),
                                  
                                // 녹화/분석 중 표시 (빨간 점)
                                if (_isAnalyzing)
                                  Positioned(
                                    top: 5,
                                    right: 5,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
  
                                // 신뢰도 점수 표시
                                if (_isAnalyzing && _confScore > 0)
                                  Positioned(
                                    top: 5,
                                    left: 5,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        "${(_confScore * 100).toInt()}%",
                                        style: TextStyle(
                                          color: _confScore >= 0.55 ? Colors.greenAccent : Colors.redAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                      ),
                    ),

                    // --- 3. 컨페티 레이어 (성공 시 전체 화면) ---
                    if (_particles.isNotEmpty)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: ConfettiPainter(_particles),
                          size: Size.infinite,
                        ),
                      ),
                    
                    // --- 4. 컨트롤 버튼 (좌측 하단) ---
                    Positioned(
                      bottom: 20,
                      left: 20,
                      child: FloatingActionButton.extended(
                        onPressed: _cameraError == null ? _toggleAnalysis : null,
                        backgroundColor: _isAnalyzing ? Colors.redAccent : Colors.indigo,
                        icon: Icon(_isAnalyzing ? Icons.stop : Icons.play_arrow),
                        label: Text(
                          _isAnalyzing ? "그만하기" : "훈련 시작", 
                          style: const TextStyle(fontWeight: FontWeight.bold)
                        ),
                      ),
                    ),
                  ],
                );
              }
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
    String statType = baseReward['stat_type'] ?? "strength";
    
    // 난이도에 따른 보상 계산
    int statReward = 1;
    int bonusPoints = 2; // 기본 보너스

    if (widget.difficulty == 'hard') {
      statReward = 3;
      bonusPoints = 5;
    }

    // 기본 보상 즉시 적용 (타겟 스탯)
    final provider = Provider.of<CharProvider>(context, listen: false);
    
    // 1. 타겟 스탯 상승
    provider.allocateStatSpecific(statType); // allocateStatSpecific는 1씩 증가하므로, 반복 호출 필요하거나 로직 수정 필요.
    // Provider의 gainReward가 이미 호출되었으므로, 여기서는 Dialog 표시만 하면 됨.
    // 하지만 gainReward 로직에 의존.
    // 중복 호출 방지를 위해 여기서는 '추가 분배'용 UI만 띄우는 것이 맞음.
    // `gainReward`가 이미 호출되었으므로, 보너스 포인트는 `unusedPoints`에 쌓여있음.
    
    // UI 표시용 데이터 준비
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        // 현재 스탯 상태 가져오기
        final currentStats = {
          "strength": provider.character?.stat?.strength ?? 0,
          "intelligence": provider.character?.stat?.intelligence ?? 0,
          "stamina": provider.character?.stat?.stamina ?? 0,
          "happiness": provider.character?.stat?.happiness ?? 0,
          "health": provider.character?.stat?.health ?? 0,
        };

        // 방금 받은 보너스를 분배하도록 유도
        return StatDistributionDialog(
          availablePoints: provider.unusedStatPoints, // 누적된 포인트 사용
          currentStats: currentStats,
          title: "🎉 훈련 성공!",
          confirmLabel: "마이룸으로 이동",
          skipLabel: "나중에 하기 (Skip)",
          onConfirm: (allocated, remaining) {
             // 할당된 포인트 적용
             // StatDistributionDialog는 UI상 변화만 보여주고, 실제 적용은 콜백에서 해야 함
             // 하지만 Provider에 이미 `unusedPoints`로 들어가 있으므로, 
             // `allocateStatSpecific`을 호출하여 차감하면서 적용해야 함.
             
             // 간편함을 위해 Dialog 내부 로직과 맞추려면:
             // Dialog는 할당량(allocated)을 반환함.
             // Provider는 'unused'에서 차감하고 스탯을 올리는 메서드가 필요.
             
             if (allocated['strength']! > 0) _applyAllocated('strength', allocated['strength']!, provider);
             if (allocated['intelligence']! > 0) _applyAllocated('intelligence', allocated['intelligence']!, provider);
             if (allocated['stamina']! > 0) _applyAllocated('stamina', allocated['stamina']!, provider);
             if (allocated['happiness']! > 0) _applyAllocated('happiness', allocated['happiness']!, provider);
             if (allocated['health']! > 0) _applyAllocated('health', allocated['health']!, provider);
             
             // 남은 포인트는 그대로 둠 (자동 저장됨)
             
             _goToMyRoom();
          },
          onSkip: () {
             // 아무것도 안 하면 포인트는 그대로 유지됨
             _goToMyRoom();
          },
        );
      },
    );
  }
  
  void _applyAllocated(String type, int amount, CharProvider provider) {
    for (int i=0; i<amount; i++) {
      provider.allocateStatSpecific(type); // 1씩 증가 및 차감
    }
  }

  void _goToMyRoom() {
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

    // 정규화된 좌표를 실제 화면 크기로 변환
    for (var kp in keypoints) {
      if (kp is List && kp.length >= 2) {
        double normX = (kp[0] as num).toDouble();
        double normY = (kp[1] as num).toDouble();
        
        // 전면 카메라 좌우 반전 고려 (필요 시 1.0 - normX)
        double finalX = (1.0 - normX) * size.width;
        double finalY = normY * size.height;
        
        points.add(Offset(finalX, finalY));
      }
    }

    // 스켈레톤 연결 정보 (COCO 포맷 기준)
    final connections = [
      [11, 13], [13, 15], [12, 14], [14, 16], // 다리
      [11, 12], [5, 6], // 몸통
      [5, 11], [6, 12], 
      [5, 7], [7, 9], [6, 8], [8, 10], // 팔
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

// 컨페티(꽃가루) 효과 그리기
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
  double x = 0.5;
  double y = 0.5;
  double vx = 0;
  double vy = 0;
  double size = 5;
  Color color = Colors.red;
  
  ConfettiParticle() {
    import_math.Random r = import_math.Random();
    x = 0.5;
    y = 0.4;
    vx = (r.nextDouble() - 0.5) * 0.05;
    vy = (r.nextDouble() - 0.5) * 0.05 - 0.02; // 위로 솟구침
    size = r.nextDouble() * 5 + 3;
    color = Color.fromARGB(255, r.nextInt(255), r.nextInt(255), r.nextInt(255));
  }
  
  void update() {
    x += vx;
    y += vy;
    vy += 0.002; // 중력 적용
  }
}
