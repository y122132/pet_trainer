import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

// 1. 데이터 모델 생성
class OutfitConfig {
  final String imagePath;
  final Rect faceArea;

  const OutfitConfig({required this.imagePath, required this.faceArea});
}

// 2. 파라미터 변경: String -> OutfitConfig
class CustomizeCharacterPage extends StatefulWidget {
  final OutfitConfig config;

  const CustomizeCharacterPage({super.key, required this.config});

  @override
  _CustomizeCharacterPageState createState() => _CustomizeCharacterPageState();
}

class _CustomizeCharacterPageState extends State<CustomizeCharacterPage> {
  ui.Image? _userImage;
  ui.Image? _outfitImage;
  bool _isLoading = false;

  // 인터랙션을 위한 상태 변수
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _loadOutfitImage(widget.config.imagePath);
    // 페이지가 빌드된 후 이미지 선택 다이얼로그를 바로 띄웁니다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showImageSourceDialog(context);
    });
  }

  Future<void> _loadOutfitImage(String assetPath) async {
    final data = await DefaultAssetBundle.of(context).load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    setState(() {
      _outfitImage = frame.image;
    });
  }

  Future<void> _showImageSourceDialog(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false, // 바깥 영역을 탭해도 닫히지 않음
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('얼굴 사진 선택'),
          content: const Text('캐릭터에 합성할 얼굴 사진을 선택하세요.'),
          actions: <Widget>[
            TextButton(
              child: const Text('카메라'),
              onPressed: () {
                Navigator.of(context).pop();
                _pickAndProcessImage(ImageSource.camera);
              },
            ),
            TextButton(
              child: const Text('갤러리'),
              onPressed: () {
                Navigator.of(context).pop();
                _pickAndProcessImage(ImageSource.gallery);
              },
            ),
             TextButton(
              child: const Text('취소'),
              onPressed: () {
                 Navigator.of(context).pop();
                 if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop(); // 이전 화면으로 돌아감
                 }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickAndProcessImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
    );

    if (pickedFile != null) {
      setState(() {
        _isLoading = true;
      });
      
      final imageFile = File(pickedFile.path);
      final imageBytes = await imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();

      setState(() {
        _userImage = frame.image;
        // 새 이미지를 선택하면 스케일과 오프셋 초기화
        _scale = 1.0;
        _offset = Offset.zero;
        _isLoading = false;
      });
    } else {
       if (mounted && Navigator.of(context).canPop()) {
         Navigator.of(context).pop();
       }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('캐릭터 커스텀'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: (_userImage != null && !_isLoading) ? () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('커스텀을 완료할까요?'),
                  content: const Text('완료된 이미지가 마이룸에 적용됩니다.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                    TextButton(
                      onPressed: () {
                         Navigator.pop(context); // 다이얼로그 닫기
                        _compositeAndSaveImage();
                      },
                      child: const Text('확인'),
                    ),
                  ],
                ),
              );
            } : null,
          ),
        ],
      ),
      body: Center(
        child: _isLoading 
          ? const CircularProgressIndicator()
          : (_userImage != null && _outfitImage != null)
            ? Stack(
                alignment: Alignment.center,
                children: [
                  GestureDetector(
                    // 2. 제스처 변경: onPanUpdate만 사용하여 이동 기능만 구현
                    onPanUpdate: (details) {
                      setState(() {
                        _offset += details.delta;
                      });
                    },
                    child: CustomPaint(
                      size: Size(_outfitImage!.width.toDouble(), _outfitImage!.height.toDouble()),
                      painter: CharacterPainter(
                        faceImage: _userImage!,
                        outfitImage: _outfitImage!,
                        scale: _scale,
                        offset: _offset,
                        faceArea: widget.config.faceArea,
                      ),
                    ),
                  ),
                  // 2. UI 변경: 확대/축소 버튼 추가
                  Positioned(
                    bottom: 32,
                    right: 32,
                    child: Column(
                      children: [
                        FloatingActionButton(
                          heroTag: 'zoom_in',
                          mini: true,
                          onPressed: () {
                            setState(() {
                              _scale += 0.1;
                            });
                          },
                          child: const Icon(Icons.add),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton(
                          heroTag: 'zoom_out',
                          mini: true,
                          onPressed: () {
                            setState(() {
                              // 최소 0.1 이하로 내려가지 않도록 제한
                              _scale = max(0.1, _scale - 0.1);
                            });
                          },
                          child: const Icon(Icons.remove),
                        ),
                      ],
                    ),
                  )
                ],
              )
            : const Text('이미지를 선택해주세요.'),
      ),
    );
  }

  Future<void> _compositeAndSaveImage() async {
    if (_userImage == null || _outfitImage == null) return;

    setState(() {
      _isLoading = true;
    });

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = CharacterPainter(
      faceImage: _userImage!,
      outfitImage: _outfitImage!,
      scale: _scale,
      offset: _offset,
      faceArea: widget.config.faceArea,
    );
    
    final size = Size(_outfitImage!.width.toDouble(), _outfitImage!.height.toDouble());
    painter.paint(canvas, size);
    
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final buffer = byteData!.buffer.asUint8List();

    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/custom_character_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(buffer);

    if (mounted) {
      Navigator.pop(context, path);
    }
  }
}

class CharacterPainter extends CustomPainter {
  final ui.Image faceImage;
  final ui.Image outfitImage;
  final double scale;
  final Offset offset;
  final Rect faceArea; // 동적으로 얼굴 영역을 받음

  CharacterPainter({
    required this.faceImage,
    required this.outfitImage,
    required this.scale,
    required this.offset,
    required this.faceArea,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // --- 1. 얼굴 이미지 그리기 (클리핑 적용) ---
    canvas.save();

    // 동적으로 전달받은 faceArea로 원형 클리핑 경로 생성
    final clipPath = Path()..addOval(faceArea);
    canvas.clipPath(clipPath);

    // 사용자의 제스처(이동, 확대/축소)를 반영하여 얼굴 이미지를 그림
    final facePaint = Paint()..filterQuality = FilterQuality.high;
    
    // 제스처의 중심점을 기준으로 변환 적용
    final faceCenter = faceArea.center + offset;
    
    final faceImageSize = Size(faceImage.width.toDouble(), faceImage.height.toDouble());
    final faceSrc = Rect.fromLTWH(0, 0, faceImageSize.width, faceImageSize.height);
    final faceDst = Rect.fromCenter(
      center: faceCenter, // 사용자가 조작한 중앙점
      width: faceImageSize.width * scale,
      height: faceImageSize.height * scale,
    );
    canvas.drawImageRect(faceImage, faceSrc, faceDst, facePaint);

    canvas.restore(); // 클리핑 상태를 복원


    // --- 2. 그 위에 옷 이미지를 합성 ---
    final outfitPaint = Paint()..filterQuality = FilterQuality.high;
    
    // TODO: 여기에서 옷의 크기와 위치를 미세 조정할 수 있습니다.
    // 예: const double scaleFactor = 0.9; // 90% 크기
    const double scaleFactor = 1.0; // 100% 크기 (변경 없음)

    final double newWidth = size.width * scaleFactor;
    final double newHeight = size.height * scaleFactor;
    final double xOffset = (size.width - newWidth) / 2;
    final double yOffset = (size.height - newHeight) / 2;
    
    final Rect outfitDestinationRect = Rect.fromLTWH(xOffset, yOffset, newWidth, newHeight);

    canvas.drawImageRect(
      outfitImage,
      Rect.fromLTWH(0, 0, outfitImage.width.toDouble(), outfitImage.height.toDouble()),
      outfitDestinationRect, // 수정된 크기와 위치
      outfitPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CharacterPainter oldDelegate) {
    return oldDelegate.faceImage != faceImage ||
        oldDelegate.outfitImage != outfitImage ||
        oldDelegate.scale != scale ||
        oldDelegate.offset != offset ||
        oldDelegate.faceArea != faceArea;
  }
}
