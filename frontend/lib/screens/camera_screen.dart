import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet_trainer_frontend/providers/char_provider.dart';
import 'package:pet_trainer_frontend/providers/training_controller.dart';
import 'package:pet_trainer_frontend/widgets/char_message_bubble.dart';
import 'package:pet_trainer_frontend/widgets/stat_distribution_dialog.dart';
import 'package:pet_trainer_frontend/widgets/camera/camera_painters.dart';
import 'my_room_page.dart'; // For navigation context if needed

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
      ResolutionPreset.medium, // High -> Medium for performance
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
       
       charProvider.fetchCharacter();
    });
  }

  void _handleSuccess() {
    _startConfetti();
    final ctrl = Provider.of<TrainingController>(context, listen: false);
    final reward = ctrl.lastReward;
    if (reward != null) {
       _showSuccessDialog(reward['base'], reward['bonus']);
    }
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

  void _toggleTraining() {
    final ctrl = Provider.of<TrainingController>(context, listen: false);
    final charProvider = Provider.of<CharProvider>(context, listen: false);
    
    if (ctrl.isAnalyzing) {
      ctrl.stopTraining();
      _cameraController.stopImageStream();
      charProvider.updateStatusMessage("분석 중지됨.");
    } else {
      ctrl.startTraining(charProvider.currentPetType, widget.difficulty, widget.mode);
      _cameraController.startImageStream((image) {
          ctrl.processFrame(image, _cameraController.description.sensorOrientation, _currentOrientation);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(_getTitle(), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
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
                         Expanded(flex: 1, child: Stack(
                            fit: StackFit.expand,
                            children: [
                               CameraPreview(_cameraController),
                               if (trainingCtrl.isAnalyzing) ...[
                                  CustomPaint(painter: DebugBoxPainter(
                                     bbox: trainingCtrl.bbox, 
                                     isFrontCamera: widget.cameras.first.lensDirection == CameraLensDirection.front,
                                     imgRatio: _cameraController.value.aspectRatio,
                                  )),
                                  if (trainingCtrl.imageWidth > 0)
                                     CustomPaint(painter: PosePainter(
                                        keypoints: trainingCtrl.keypoints,
                                        feedback: trainingCtrl.feedback,
                                        isFrontCamera: widget.cameras.first.lensDirection == CameraLensDirection.front,
                                        imgRatio: _cameraController.value.aspectRatio,

                                     ))
                               ],
                               
                               // STAY Progress
                               if (trainingCtrl.trainingState == TrainingStatus.stay)
                                  Container(color: Colors.black38, child: Center(child: Column(
                                     mainAxisSize: MainAxisSize.min,
                                     children: [
                                        CircularProgressIndicator(value: trainingCtrl.stayProgress, strokeWidth: 8, valueColor: const AlwaysStoppedAnimation(Colors.greenAccent)),
                                        const SizedBox(height: 10),
                                        Text(trainingCtrl.progressText, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))
                                     ]
                                  ))),
                                  
                               // Debug Info
                               if (trainingCtrl.isAnalyzing)
                                  Positioned(top: 10, left: 10, child: Container(
                                     padding: const EdgeInsets.all(8),
                                     decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                     child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text("Status: ${trainingCtrl.trainingState.name.toUpperCase()}", style: const TextStyle(color: Colors.white, fontSize: 10)),
                                        Text("Score: ${(trainingCtrl.confScore * 100).toStringAsFixed(1)}%", style: const TextStyle(color: Colors.greenAccent, fontSize: 10)),
                                        Text("Latency: ${trainingCtrl.latency}ms", style: const TextStyle(color: Colors.white, fontSize: 10)),
                                     ])
                                  ))
                            ]
                         )),
                         // Character Area
                         Expanded(flex: 1, child: Container(
                            width: double.infinity, color: Colors.white,
                            child: Column(children: [
                               Expanded(child: Image.asset(charProvider.character?.imageUrl ?? "assets/images/characters/닌자옷.png", fit: BoxFit.contain)),
                               ChatBubble(message: charProvider.statusMessage, isAnalyzing: trainingCtrl.isAnalyzing)
                            ])
                         ))
                      ];
                      
                      return Stack(children: [
                         isLandscape ? Row(children: children) : Column(children: children),
                         if (_particles.isNotEmpty) IgnorePointer(child: CustomPaint(painter: ConfettiPainter(_particles), size: Size.infinite)),
                         Positioned(
                            bottom: isLandscape ? 20 : 150, left: 0, right: 0,
                            child: Center(child: FloatingActionButton.extended(
                               onPressed: _toggleTraining,
                               backgroundColor: trainingCtrl.isAnalyzing ? Colors.redAccent : Colors.indigo,
                               icon: Icon(trainingCtrl.isAnalyzing ? Icons.stop : Icons.play_arrow),
                               label: Text(trainingCtrl.isAnalyzing ? "STOP" : "START", style: const TextStyle(fontWeight: FontWeight.bold))
                            ))
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

  void _showSuccessDialog(Map<String, dynamic> baseReward, int bonus) {
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
    
    showDialog(
       context: context, barrierDismissible: false,
       builder: (ctx) => StatDistributionDialog(
          availablePoints: charProvider.unusedStatPoints,
          currentStats: currentStats,
          title: "🎉 훈련 성공!",
          earnedReward: baseReward,
          earnedBonus: bonus,
          confirmLabel: "마이룸으로 이동",
          skipLabel: "나중에 하기",
          onConfirm: (allocated, remaining) {
             ['strength','intelligence','agility','defense','luck'].forEach((key) {
                for(int i=0; i < (allocated[key]??0); i++) charProvider.allocateStatSpecific(key);
             });
             _goToMyRoom();
          },
          onSkip: _goToMyRoom,
          onContinue: () {
             Navigator.pop(ctx);
             _toggleTraining(); // Restart
          },
       )
    );
  }
  
  void _goToMyRoom() {
     Navigator.pop(context); // Dialog
     Navigator.pop(context); // Camera Screen
  }
}