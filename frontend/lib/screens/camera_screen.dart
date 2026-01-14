import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet_trainer_frontend/providers/char_provider.dart';
import 'package:pet_trainer_frontend/providers/training_controller.dart';
import 'package:pet_trainer_frontend/widgets/char_message_bubble.dart';
import 'package:pet_trainer_frontend/widgets/stat_distribution_dialog.dart';
import 'package:pet_trainer_frontend/widgets/camera/camera_painters.dart';
import 'package:pet_trainer_frontend/api_config.dart'; // [Fix] Import AppConfig
import 'package:pet_trainer_frontend/config/theme.dart';
import 'package:pet_trainer_frontend/config/design_system.dart';
import 'my_room_page.dart'; // For navigation context if needed
import 'skill_management_screen.dart';

class CameraScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  final String difficulty;
  final String mode;

  const CameraScreen({
    super.key, 
    required this.cameras, 
    this.mode = 'exercise', 
    this.difficulty = 'easy'
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TrainingController(),
      child: _CameraView(cameras: cameras, mode: mode, difficulty: difficulty),
    );
  }
}

class _CameraView extends StatefulWidget {
  final List<CameraDescription> cameras;
  final String mode;
  final String difficulty;

  const _CameraView({required this.cameras, required this.mode, required this.difficulty});

  @override
  State<_CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<_CameraView> with TickerProviderStateMixin {
  late CameraController _cameraController;
  late Future<void> _initFuture;
  late AnimationController _confettiController;
  List<ConfettiParticle> _particles = [];
  Orientation _currentOrientation = Orientation.portrait;

  @override
  void initState() {
    super.initState();
    _cameraController = CameraController(
      widget.cameras.first,
      ResolutionPreset.medium, // High (720p) -> Best for 1280px inference
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _initFuture = _cameraController.initialize();

    _confettiController = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..addListener(() {
        if (mounted) setState(() { for (var p in _particles) p.update(); });
      });
      
    WidgetsBinding.instance.addPostFrameCallback((_) {
       // Link CharProvider to TrainingController
       final trainingCtrl = Provider.of<TrainingController>(context, listen: false);
       final charProvider = Provider.of<CharProvider>(context, listen: false);
       
       trainingCtrl.setCharProvider(charProvider);
       trainingCtrl.onSuccessCallback = _handleSuccess;
       
       // [Fix] Load My Character instead of default (1)
       charProvider.fetchMyCharacter();
    });
  }

  void _handleSuccess() {
    print("🎉 _handleSuccess Triggered!"); 
    // Schedule dialog for AFTER the current build cycle (which might be triggered by stopTraining)
    WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        print("🎉 Showing Success Dialog...");
        _startConfetti();
        final ctrl = Provider.of<TrainingController>(context, listen: false);
        final reward = ctrl.lastReward;
        if (reward != null) {
           _showSuccessDialog(reward['base'], reward['bonus'], reward['level_up_info']);
        } else {
           print("⚠️ Last Reward is NULL!");
        }
    });
  }

  void _startConfetti() {
    setState(() => _particles = List.generate(50, (_) => ConfettiParticle()));
    _confettiController.forward(from: 0);
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _toggleTraining() async {
    final ctrl = Provider.of<TrainingController>(context, listen: false);
    final charProvider = Provider.of<CharProvider>(context, listen: false);
    
    if (ctrl.isAnalyzing) {
      ctrl.stopTraining();
      await _cameraController.stopImageStream();
      charProvider.updateStatusMessage("분석 중지됨.");
    } else {
      // [DEBUG] PROBE 1: User Clicked Start
      print("⭕ [PROBE 1] User Pressed START");
      
      // [Fix] Await initialization so EdgeDetector is ready before frames flow
      await ctrl.startTraining(charProvider.currentPetType, widget.difficulty, widget.mode);
      
      // Only start stream if training started successfully
      if (ctrl.isAnalyzing) {
          print("⭕ [PROBE 3] Starting Camera Stream...");
          await _cameraController.startImageStream((image) {
              // print("⭕ [PROBE 4] Camera Yielded Frame"); // Comment out to avoid spam, or keep for 1st frame check
              ctrl.processFrame(image, _cameraController.description.sensorOrientation, _currentOrientation);
          });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text(_getTitle(), style: AppTextStyles.title.copyWith(fontSize: 20)),
          backgroundColor: Colors.transparent, // Glass effect via flexibleSpace if needed, or simple transparent
          elevation: 0,
          centerTitle: true,
          leading: Container(
             margin: const EdgeInsets.only(left: 8, top: 8, bottom: 8),
             decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), shape: BoxShape.circle),
             child: IconButton(
               icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textMain, size: 20),
               onPressed: () => Navigator.pop(context),
             ),
          ),
        ),
        body: FutureBuilder<void>(
          future: _initFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
               return Consumer2<TrainingController, CharProvider>(
                 builder: (context, trainingCtrl, charProvider, child) {
                   return OrientationBuilder(
                     builder: (context, orientation) {
                        if (_currentOrientation != orientation) _currentOrientation = orientation;
                        final isLandscape = orientation == Orientation.landscape;
                        
                        List<Widget> children = [
                           // --- Camera View Area ---
                           Expanded(flex: 2, child: Stack(
                              fit: StackFit.expand,
                              children: [
                                 ClipRRect(
                                    borderRadius: BorderRadius.circular(isLandscape ? 0 : 30),
                                    child: CameraPreview(_cameraController)
                                 ),
                                 if (trainingCtrl.isAnalyzing) ...[
                                    CustomPaint(painter: DebugBoxPainter(
                                       bbox: trainingCtrl.bbox, 
                                       isFrontCamera: widget.cameras.first.lensDirection == CameraLensDirection.front,
                                       imgRatio: _cameraController.value.aspectRatio,
                                    )),
                                    // Pet Skeleton
                                    if (trainingCtrl.petKeypoints.isNotEmpty)
                                       CustomPaint(painter: PetPosePainter(
                                          keypoints: trainingCtrl.petKeypoints,
                                          isFrontCamera: widget.cameras.first.lensDirection == CameraLensDirection.front,
                                          imgRatio: _cameraController.value.aspectRatio,
                                       )),
                                     
                                     // [NEW] Model Input Image Thumbnail (Debug)
                                     /* // Hidden for aesthetic mode unless dev usage
                                     if (trainingCtrl.debugInputImage != null)
                                        Positioned(top: 10, right: 10, child: Container(
                                           ...
                                        )),
                                     */
                                       
                                    // Human Skeleton (Legacy or New)
                                    if (trainingCtrl.humanKeypoints.isNotEmpty || trainingCtrl.keypoints.isNotEmpty)
                                       CustomPaint(painter: PosePainter(
                                          keypoints: trainingCtrl.humanKeypoints.isNotEmpty ? trainingCtrl.humanKeypoints : trainingCtrl.keypoints,
                                          feedback: trainingCtrl.feedback,
                                          isFrontCamera: widget.cameras.first.lensDirection == CameraLensDirection.front,
                                          imgRatio: _cameraController.value.aspectRatio,
                                       ))
                                 ],
                                 
                                 // STAY Progress
                                 if (trainingCtrl.trainingState == TrainingStatus.stay)
                                 // STAY Progress (Moved to Top)
                                 if (trainingCtrl.trainingState == TrainingStatus.stay)
                                    Positioned(
                                      top: 80, // Below App Bar
                                      left: 40, right: 40,
                                      child: GlassContainer(
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                        borderRadius: BorderRadius.circular(20),
                                        child: Column(
                                         mainAxisSize: MainAxisSize.min,
                                         children: [
                                            Text(trainingCtrl.progressText, style: AppTextStyles.title.copyWith(fontSize: 18, color: AppColors.textMain)),
                                            const SizedBox(height: 8),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(10),
                                              child: LinearProgressIndicator(
                                                value: trainingCtrl.stayProgress, 
                                                minHeight: 12,
                                                backgroundColor: Colors.grey.withOpacity(0.3),
                                                valueColor: const AlwaysStoppedAnimation(AppColors.primaryMint),
                                              ),
                                            ),
                                         ]
                                      ))
                                    ),
                                    
                                 // Debug Info Overlay (Top Left)
                                 if (trainingCtrl.isAnalyzing)
                                    Positioned(
                                      top: 10, left: 10, 
                                      child: GlassContainer(
                                        padding: const EdgeInsets.all(8),
                                        borderRadius: BorderRadius.circular(12),
                                        opacity: 0.7,
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text("Status: ${trainingCtrl.trainingState.name.toUpperCase()}", style: const TextStyle(color: AppColors.textMain, fontSize: 10, fontWeight: FontWeight.bold)),
                                          Text("Score: ${(trainingCtrl.confScore * 100).toStringAsFixed(1)}%", style: const TextStyle(color: AppColors.success, fontSize: 10)),
                                          Text("Lat: ${trainingCtrl.inferenceMs}ms", style: const TextStyle(color: AppColors.textSub, fontSize: 10)),
                                       ])
                                    )),
                                    
                              ]
                           )),

                           // --- Side/Bottom Panel with Character ---
                           Expanded(flex: 1, child: Container(
                              width: double.infinity, 
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: isLandscape ? const BorderRadius.horizontal(left: Radius.circular(30)) : const BorderRadius.vertical(top: Radius.circular(30)),
                                boxShadow: AppDecorations.softShadow,
                              ),
                              child: Column(children: [
                                const SizedBox(height: 10),
                                Expanded(child: Builder(
                                  builder: (context) {
                                    final char = charProvider.character;
                                    String? imageUrl = char?.frontUrl;
                                    
                                    if (imageUrl != null && imageUrl.isNotEmpty) {
                                         if (imageUrl.startsWith('/')) {
                                             imageUrl = "${AppConfig.serverBaseUrl}$imageUrl";
                                         } else if (imageUrl.contains('localhost')) {
                                             imageUrl = imageUrl.replaceFirst('localhost', AppConfig.serverIp);
                                         }
                                         return Image.network(imageUrl!, fit: BoxFit.contain);
                                    } else {
                                         // Fallback Asset
                                         return Image.asset(char?.imagePath ?? "assets/images/characters/닌자옷.png", fit: BoxFit.contain);
                                    }
                                  }
                                )),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                  child: CharMessageBubble(message: charProvider.statusMessage, isAnalyzing: trainingCtrl.isAnalyzing),
                                ),
                                const SizedBox(height: 20),
                              ])
                           ))
                        ];
                        
                        return Stack(children: [
                           isLandscape ? Row(children: children) : Column(children: children),
                           
                           if (_particles.isNotEmpty) IgnorePointer(child: CustomPaint(painter: ConfettiPainter(_particles), size: Size.infinite)),
                           
                           // Floating Action Button for Start/Stop (Global Overlay)
                           Positioned(
                              bottom: isLandscape ? 20 : 180, // Adjust position based on orientation
                              left: 0, right: 0,
                              child: Center(
                                child: SizedBox(
                                  height: 60, width: 140,
                                  child: ElevatedButton.icon(
                                     onPressed: _toggleTraining,
                                     style: ElevatedButton.styleFrom(
                                       backgroundColor: trainingCtrl.isAnalyzing ? AppColors.danger : AppColors.primaryMint,
                                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                       elevation: 6,
                                     ),
                                     icon: Icon(trainingCtrl.isAnalyzing ? Icons.stop_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 30),
                                     label: Text(trainingCtrl.isAnalyzing ? "STOP" : "START", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white))
                                  ),
                                )
                              )
                           )
                        ]);
                     }
                   );
                 }
               );
            } else {
               return const Center(child: CircularProgressIndicator());
            }
          }
        ),
      ),
    );
  }
  
  String _getTitle() {
    switch(widget.mode) {
      case 'feeding': return '🥣 식사';
      case 'playing': return '🎾 놀이';
      case 'interaction': return '🤝 교감';
      default: return '훈련장';
    }
  }

  Future<void> _showSuccessDialog(Map<String, dynamic> baseReward, int bonus, dynamic levelUpInfo) async {
    if (!mounted) return;
    final charProvider = Provider.of<CharProvider>(context, listen: false);
    final trainingCtrl = Provider.of<TrainingController>(context, listen: false);
    
    final currentStats = {
      "strength": charProvider.strength,
      "intelligence": charProvider.intelligence,
      "agility": charProvider.agility,
      "defense": charProvider.defense,
      "luck": charProvider.luck,
    };
    
    await showDialog(
       context: context, barrierDismissible: false,
       builder: (ctx) => StatDistributionDialog(
          availablePoints: charProvider.unusedStatPoints,
          currentStats: currentStats,
          title: "🎉 훈련 성공!",
          earnedReward: baseReward,
          earnedBonus: bonus,
          // No specialMessage
          confirmLabel: "마이룸으로 이동",
          skipLabel: "나중에 하기",
          onConfirm: (allocated, remaining) {
             ['strength','intelligence','agility','defense','luck'].forEach((key) {
                for(int i=0; i < (allocated[key]??0); i++) charProvider.allocateStatSpecific(key);
             });
             Navigator.pop(ctx); // Close Stat Dialog
          },
          onSkip: () => Navigator.pop(ctx), // Close Stat Dialog
          onContinue: () {
             Navigator.pop(ctx);
             _toggleTraining(); // Restart
          },
       )
    );

    // Check Skills & Navigate
    _handleSkillAndExit(levelUpInfo);
  }

  void _handleSkillAndExit(dynamic levelUpInfo) {
      if (!mounted) return;
      final skills = levelUpInfo?['acquired_skills_details'];
      
      if (skills != null && (skills as List).isNotEmpty) {
          String msg = "";
          for (var s in skills) {
             msg += "'${s['name']}' ";
          }
          msg += "스킬을 획득했습니다!\n스킬 창으로 이동하시겠습니까?";
          
          showDialog(
             context: context,
             barrierDismissible: false,
             builder: (context) => AlertDialog(
                 title: const Text("스킬 획득!"),
                 content: Text(msg),
                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                 actions: [
                    TextButton(
                       onPressed: () { 
                          Navigator.pop(context); 
                          _goToMyRoom();
                       },
                       child: const Text("아니오 (마이룸)", style: TextStyle(color: AppColors.textSub)),
                    ),
                    ElevatedButton(
                       onPressed: () {
                          Navigator.pop(context); // Close Alert
                          Navigator.pop(context); // Close Camera
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const SkillManagementScreen()));
                       },
                       child: const Text("예 (이동)"),
                    ),
                 ]
             )
          );
      } else {
          _goToMyRoom();
      }
  }
  
  void _goToMyRoom() {
     // Dialog is already closed by 'await showDialog' or explicit pop in actions
     // We only need to close the Camera Screen
     if (mounted) Navigator.pop(context); 
  }

  String? _buildSkillMessage(dynamic levelUpInfo) {
      if (levelUpInfo == null) return null;
      final skills = levelUpInfo['acquired_skills_details'];
      if (skills != null && (skills as List).isNotEmpty) {
          String msg = "";
          for (var s in skills) {
             msg += "\n[${s['level']}]레벨 달성! '${s['name']}' 스킬 획득!";
          }
          return msg;
      }
      return null;
  }
}