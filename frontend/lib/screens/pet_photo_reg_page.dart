import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:pet_trainer_frontend/api_config.dart';
import 'package:pet_trainer_frontend/config/theme.dart';
import 'package:pet_trainer_frontend/providers/char_provider.dart';
import 'package:pet_trainer_frontend/screens/menu_page.dart';
import 'package:pet_trainer_frontend/screens/take_photo_page.dart';
import 'package:provider/provider.dart';

class PetPhotoRegistrationPage extends StatefulWidget {
  final String petName;

  const PetPhotoRegistrationPage({super.key, required this.petName});

  @override
  _PetPhotoRegistrationPageState createState() =>
      _PetPhotoRegistrationPageState();
}

class _PetPhotoRegistrationPageState extends State<PetPhotoRegistrationPage> {
  final Map<String, XFile?> _images = {
    'Front': null,
    'Back': null,
    'Side': null,
    'Face': null,
  };
  final Map<String, String> _labels = {
    'Front': '정면',
    'Back': '후면',
    'Side': '옆면',
    'Face': '얼굴',
  };

  final ImagePicker _picker = ImagePicker();
  final _storage = const FlutterSecureStorage();
  bool _isUploading = false;

  void _showImageSourceActionSheet(String key) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
        );
      },
    );
  }

  Future<void> _takePicture(String key) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const TakePhotoPage()),
    );

    if (result is XFile) {
      setState(() {
        _images[key] = result;
      });
    }
  }

  Future<void> _pickImageFromGallery(String key) async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _images[key] = pickedFile;
      });
    }
  }

  bool _areAllImagesSelected() {
    return _images.values.every((image) => image != null);
  }

  void _submit() async {
    if (!_areAllImagesSelected()) return;

    final pageContext = context;

    showDialog(
      context: pageContext,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('캐릭터 등록'),
          content: const Text(
              '캐릭터 등록을 마치시겠습니까?\n*추후 설정에서 사진을 변경하실 수 있습니다.'),
          actions: <Widget>[
            TextButton(
              child: const Text('아니오'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('예'),
              onPressed: () async {
                Navigator.of(dialogContext).pop(); 
                
                setState(() {
                  _isUploading = true;
                });
                
                bool success = false;
                try {
                  // 1. Get user_id and token
                  final token = await _storage.read(key: 'jwt_token');
                  final userId = await _storage.read(key: 'user_id');
                  if (token == null || userId == null) {
                    throw Exception("로그인 정보가 없습니다.");
                  }

                  // 2. Create Character
                  final createResponse = await http.post(
                    Uri.parse("${AppConfig.charactersUrl}/"),
                    headers: {
                      "Content-Type": "application/json; charset=UTF-8",
                      "Authorization": "Bearer $token"
                    },
                    body: jsonEncode({
                      "user_id": int.parse(userId),
                      "name": widget.petName,
                    }),
                  );

                  if (createResponse.statusCode != 200 && createResponse.statusCode != 201) {
                    throw Exception("캐릭터 생성 실패: ${createResponse.body}");
                  }
                  
                  final responseData = jsonDecode(utf8.decode(createResponse.bodyBytes));
                  final newCharId = responseData['id'];
                  if (newCharId == null) {
                    throw Exception("캐릭터 ID를 받아오지 못했습니다.");
                  }

                  // 3. Update Image URLs (using local paths as mock URLs)
                  final imageUpdateResponse = await http.put(
                    Uri.parse("${AppConfig.charactersUrl}/$newCharId/images"),
                    headers: {
                      "Content-Type": "application/json; charset=UTF-8",
                      "Authorization": "Bearer $token"
                    },
                    body: jsonEncode({
                      "front_url": _images['Front']!.path,
                      "back_url": _images['Back']!.path,
                      "side_url": _images['Side']!.path,
                      "face_url": _images['Face']!.path,
                    }),
                  );

                  if (imageUpdateResponse.statusCode != 200) {
                     throw Exception("이미지 URL 업데이트 실패: ${imageUpdateResponse.body}");
                  }
                  
                  // 4. Save character ID and update provider
                  await _storage.write(key: 'character_id', value: newCharId.toString());
                  success = true;

                } catch (e) {
                   if (mounted) {
                    ScaffoldMessenger.of(pageContext).showSnackBar(
                      SnackBar(content: Text('오류 발생: $e')),
                    );
                   }
                } finally {
                   if (mounted) {
                    setState(() {
                      _isUploading = false;
                    });
                   }
                }
                
                if (success) {
                  Provider.of<CharProvider>(pageContext, listen: false)
                      .setTemporaryImages(_images);
                  
                  Navigator.of(pageContext).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const MenuPage(),
                    ),
                    (Route<dynamic> route) => false,
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.petName}의 사진 등록', style: Theme.of(context).textTheme.titleLarge),
        backgroundColor: AppColors.creamWhite,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  '${widget.petName}의 사진을 등록해주세요',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    children: _images.keys.map((String key) {
                      return _buildPhotoSlot(key);
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _areAllImagesSelected() ? const Color(0xFFD6A579) : Colors.grey,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: _areAllImagesSelected() && !_isUploading ? _submit : null,
                  child: Text(
                    '완료',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isUploading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('사진을 등록하는 중...', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoSlot(String key) {
    XFile? image = _images[key];
    String label = _labels[key]!;

    Widget imageWidget;
    if (image == null) {
      imageWidget = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt, size: 50, color: Colors.grey[600]),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: Colors.grey[800])),
        ],
      );
    } else {
      if (kIsWeb) {
        imageWidget = Image.network(
          image.path,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      } else {
        imageWidget = Image.file(
          File(image.path),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      }
    }
    
    return GestureDetector(
      onTap: () => _showImageSourceActionSheet(key),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: imageWidget,
        ),
      ),
    );
  }
}
