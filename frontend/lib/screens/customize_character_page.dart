import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class CustomizeCharacterPage extends StatefulWidget {
  final File imageFile;

  const CustomizeCharacterPage({super.key, required this.imageFile});

  @override
  _CustomizeCharacterPageState createState() => _CustomizeCharacterPageState();
}

class _CustomizeCharacterPageState extends State<CustomizeCharacterPage> {
  final List<String> _outfitImages = [
    'assets/images/characters/공주옷.png',
    'assets/images/characters/닌자옷.png',
    'assets/images/characters/멜빵옷.png',
    'assets/images/characters/바나나옷.png',
  ];

  int _selectedOutfitIndex = 0;
  ui.Image? _userImage;
  ui.Image? _selectedOutfitImage;

  @override
  void initState() {
    super.initState();
    _loadImage(widget.imageFile);
    _loadOutfitImage(_outfitImages[_selectedOutfitIndex]);
  }

  Future<void> _loadImage(File file) async {
    final data = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    setState(() {
      _userImage = frame.image;
    });
  }

  Future<void> _loadOutfitImage(String assetPath) async {
    final data = await DefaultAssetBundle.of(context).load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    setState(() {
      _selectedOutfitImage = frame.image;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('캐릭터 커스텀'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _compositeAndSaveImage,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Center(
              child: _userImage != null && _selectedOutfitImage != null
                  ? CustomPaint(
                      size: const Size(300, 300),
                      painter: CharacterPainter(
                        userImage: _userImage!,
                        outfitImage: _selectedOutfitImage!,
                      ),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
          Expanded(
            flex: 1,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 1,
              ),
              itemCount: _outfitImages.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedOutfitIndex = index;
                      _loadOutfitImage(_outfitImages[index]);
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _selectedOutfitIndex == index
                            ? Colors.blue
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Image.asset(_outfitImages[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _compositeAndSaveImage() async {
    if (_userImage == null || _selectedOutfitImage == null) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = CharacterPainter(
      userImage: _userImage!,
      outfitImage: _selectedOutfitImage!,
    );
    painter.paint(canvas, const Size(300, 300));
    final picture = recorder.endRecording();
    final img = await picture.toImage(300, 300);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final buffer = byteData!.buffer.asUint8List();

    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/custom_character.png';
    final file = File(path);
    await file.writeAsBytes(buffer);

    Navigator.pop(context, path);
  }
}

class CharacterPainter extends CustomPainter {
  final ui.Image userImage;
  final ui.Image outfitImage;

  CharacterPainter({required this.userImage, required this.outfitImage});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the outfit first
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, size.width, size.height),
      image: outfitImage,
      fit: BoxFit.contain,
    );

    // Then draw the user's image on top
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(size.width * 0.25, size.height * 0.1, size.width * 0.5, size.height * 0.5), // Adjust the position and size as needed
      image: userImage,
      fit: BoxFit.cover,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}
