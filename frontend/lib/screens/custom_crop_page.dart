import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

class CustomCropPage extends StatefulWidget {
  final File imageFile;
  final String outfitImagePath;

  const CustomCropPage({super.key, required this.imageFile, required this.outfitImagePath});

  @override
  _CustomCropPageState createState() => _CustomCropPageState();
}

class _CustomCropPageState extends State<CustomCropPage> {
  final GlobalKey _imageKey = GlobalKey();
  ui.Image? _image;
  ui.Image? _outfitImage;
  double _scale = 1.0;
  double _previousScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _previousOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _loadImage();
    _loadOutfitImage();
  }

  Future<void> _loadImage() async {
    final data = await widget.imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    setState(() {
      _image = frame.image;
    });
  }

  Future<void> _loadOutfitImage() async {
    final data = await DefaultAssetBundle.of(context).load(widget.outfitImagePath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    setState(() {
      _outfitImage = frame.image;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('얼굴 영역 선택'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _cropImage,
          ),
        ],
      ),
      body: Center(
        child: GestureDetector(
          onScaleStart: (details) {
            _previousScale = _scale;
            _previousOffset = details.focalPoint;
          },
          onScaleUpdate: (details) {
            setState(() {
              _scale = _previousScale * details.scale;
              _offset += details.focalPoint - _previousOffset;
              _previousOffset = details.focalPoint;
            });
          },
          child: RepaintBoundary(
            key: _imageKey,
            child: Stack(
              children: [
                if (_image != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: ImagePainter(_image!, _scale, _offset),
                    ),
                  ),
                if (_outfitImage != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: OutfitPainter(_outfitImage!),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cropImage() async {
    RenderRepaintBoundary boundary = _imageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage();
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    Uint8List pngBytes = byteData!.buffer.asUint8List();

    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/cropped_image.png';
    final file = File(path);
    await file.writeAsBytes(pngBytes);

    Navigator.pop(context, {'path': path, 'scale': _scale, 'offset': _offset});
  }
}

class ImagePainter extends CustomPainter {
  final ui.Image image;
  final double scale;
  final Offset offset;

  ImagePainter(this.image, this.scale, this.offset);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final center = size.center(Offset.zero) + offset;
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final src = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
    final dst = Rect.fromCenter(
      center: center,
      width: imageSize.width * scale,
      height: imageSize.height * scale,
    );
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}

class OutfitPainter extends CustomPainter {
  final ui.Image outfitImage;

  OutfitPainter(this.outfitImage);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final imageSize = Size(outfitImage.width.toDouble(), outfitImage.height.toDouble());
    final src = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
    final dst = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width,
      height: size.height,
    );
    canvas.drawImageRect(outfitImage, src, dst, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
