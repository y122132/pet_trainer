import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:pet_trainer_frontend/models/character_model.dart';
import 'package:pet_trainer_frontend/providers/char_provider.dart';
import 'package:pet_trainer_frontend/api_config.dart';
import 'camera_screen.dart';

class CharacterImageUpdateScreen extends StatefulWidget {
  final Character character;

  const CharacterImageUpdateScreen({super.key, required this.character});

  @override
  State<CharacterImageUpdateScreen> createState() => _CharacterImageUpdateScreenState();
}

class _CharacterImageUpdateScreenState extends State<CharacterImageUpdateScreen> {
  final ImagePicker _picker = ImagePicker();
  final Map<String, XFile?> _newImages = {
    'front_url': null,
    'back_url': null,
    'side_url': null,
    'face_url': null,
  };
  final Map<String, String> _labels = {
    'front_url': '정면',
    'back_url': '후면',
    'side_url': '옆면',
    'face_url': '얼굴',
  };

  bool _isLoading = false;
  String? _loadingKey;

  void _showImageSourceActionSheet(String key) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('카메라로 촬영'),
              onTap: () {
                Navigator.of(context).pop();
                _takePicture(key);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('갤러리에서 선택'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImageFromGallery(key);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _takePicture(String key) async {
    final cameras = await availableCameras();
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => CameraScreen(cameras: cameras)),
    );

    if (result is XFile) {
      setState(() {
        _newImages[key] = result;
      });
    }
  }

  Future<void> _pickImageFromGallery(String key) async {
    try {
      final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _newImages[key] = pickedFile;
        });
      }
    } catch (e) {
      debugPrint("Gallery Error: $e");
    }
  }

  Future<void> _updateImage(String imageKey) async {
    final newImageFile = _newImages[imageKey];
    if (newImageFile == null) return;

    setState(() {
      _isLoading = true;
      _loadingKey = imageKey;
    });

    try {
      final provider = Provider.of<CharProvider>(context, listen: false);
      bool success = await provider.updateCharacterImage(widget.character.id!, imageKey, newImageFile);

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("이미지가 성공적으로 업데이트되었습니다!")));
        await provider.fetchMyCharacter();
        setState(() {
          _newImages[imageKey] = null;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(provider.statusMessage ?? "이미지 업데이트 실패")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("오류가 발생했습니다: $e")));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingKey = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("캐릭터 사진 변경"),
      ),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        children: _labels.keys.map((key) {
          final label = _labels[key]!;
          final newImage = _newImages[key];
          String? currentImageUrl;
          switch (key) {
            case 'front_url':
              currentImageUrl = widget.character.frontUrl;
              break;
            case 'back_url':
              currentImageUrl = widget.character.backUrl;
              break;
            case 'side_url':
              currentImageUrl = widget.character.sideUrl;
              break;
            case 'face_url':
              currentImageUrl = widget.character.faceUrl;
              break;
          }

          Widget imageWidget;
          if (newImage != null) {
            imageWidget = kIsWeb ? Image.network(newImage.path, fit: BoxFit.cover) : Image.file(File(newImage.path), fit: BoxFit.cover);
          } else if (currentImageUrl != null && currentImageUrl.isNotEmpty) {
            String fullUrl = currentImageUrl;
            if (fullUrl.startsWith('/')) {
              fullUrl = "${AppConfig.serverBaseUrl}$fullUrl";
            }
            imageWidget = Image.network(
              fullUrl,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.pets, color: Colors.grey, size: 40),
            );
          } else {
            imageWidget = Center(child: Text(label));
          }
          
          return GestureDetector(
            onTap: () => _showImageSourceActionSheet(key),
            child: GridTile(
              footer: Container(
                color: Colors.black54,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white)),
                    if (_isLoading && _loadingKey == key)
                      const Padding(
                        padding: EdgeInsets.only(left: 8.0),
                        child: SizedBox(height: 12, width: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      ),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Container(
                    color: Colors.grey[200],
                    child: imageWidget,
                  ),
                  if (newImage != null)
                    Positioned(
                      bottom: 40,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : () => _updateImage(key),
                          child: const Text("저장"),
                        ),
                      ),
                    )
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
