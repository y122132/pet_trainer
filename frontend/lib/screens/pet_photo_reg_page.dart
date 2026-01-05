import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pet_trainer_frontend/api_config.dart';
import 'package:pet_trainer_frontend/providers/char_provider.dart';
import 'package:pet_trainer_frontend/screens/menu_page.dart';
import 'package:pet_trainer_frontend/screens/take_photo_page.dart';
import 'package:provider/provider.dart';
import '../config/design_system.dart';

class PetPhotoRegistrationPage extends StatefulWidget {
  final String petName;

  const PetPhotoRegistrationPage({super.key, required this.petName});

  @override
  _PetPhotoRegistrationPageState createState() =>
      _PetPhotoRegistrationPageState();
}

class _PetPhotoRegistrationPageState extends State<PetPhotoRegistrationPage> {
  final Map<String, XFile?> _images = {
    'Front': null, 'Back': null, 'Side': null, 'Face': null,
  };
  final Map<String, String> _labels = {
    'Front': '정면', 'Back': '후면', 'Side': '옆면', 'Face': '얼굴',
  };

  final ImagePicker _picker = ImagePicker();
  final _storage = const FlutterSecureStorage();
  bool _isUploading = false;

  void _showImageSourceActionSheet(String key) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const FaIcon(FontAwesomeIcons.camera, color: AppColors.primaryBrown),
                title: Text('카메라로 촬영', style: AppTextStyles.body),
                onTap: () {
                  Navigator.of(context).pop();
                  _takePicture(key);
                },
              ),
              ListTile(
                leading: const FaIcon(FontAwesomeIcons.photoFilm, color: AppColors.primaryBrown),
                title: Text('갤러리에서 선택', style: AppTextStyles.body),
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
    if (result is XFile) setState(() => _images[key] = result);
  }

  Future<void> _pickImageFromGallery(String key) async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _images[key] = pickedFile);
  }

  bool _areAllImagesSelected() => _images.values.every((image) => image != null);

  void _submit() async {
    if (!_areAllImagesSelected()) return;
    final pageContext = context;

    showDialog(
        context: pageContext,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius),
              backgroundColor: AppColors.background,
              title: Text('캐릭터 등록', style: AppTextStyles.title.copyWith(fontSize: 22)),
              content: Text('캐릭터 등록을 마치시겠습니까?\n*추후 설정에서 사진을 변경하실 수 있습니다.', style: AppTextStyles.body),
              actions: <Widget>[
                TextButton(
                  child: Text('아니오', style: AppTextStyles.body),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBrown,
                      shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius)),
                  child: Text('예', style: AppTextStyles.button),
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    setState(() => _isUploading = true);
                    bool success = false;
                    try {
                      final token = await _storage.read(key: 'jwt_token');
                      final userId = await _storage.read(key: 'user_id');
                      if (token == null || userId == null) throw Exception("로그인 정보가 없습니다.");
                      
                      final createResponse = await http.post(
                        Uri.parse("${AppConfig.charactersUrl}/"),
                        headers: {"Content-Type": "application/json; charset=UTF-8", "Authorization": "Bearer $token"},
                        body: jsonEncode({"user_id": int.parse(userId), "name": widget.petName}),
                      );
                      if (createResponse.statusCode > 201) throw Exception("캐릭터 생성 실패: ${createResponse.body}");
                      
                      final responseData = jsonDecode(utf8.decode(createResponse.bodyBytes));
                      final newCharId = responseData['id'];
                      if (newCharId == null) throw Exception("캐릭터 ID를 받아오지 못했습니다.");
                      
                      var request = http.MultipartRequest('PUT', Uri.parse("${AppConfig.charactersUrl}/$newCharId/images"));
                      request.headers['Authorization'] = 'Bearer $token';

                      for (var entry in _images.entries) {
                        String key = entry.key;
                        XFile imageFile = entry.value!;
                        String fieldName = '${key.toLowerCase()}_image';
                        if (kIsWeb) {
                          request.files.add(http.MultipartFile.fromBytes(fieldName, await imageFile.readAsBytes(), filename: imageFile.name));
                        } else {
                          request.files.add(await http.MultipartFile.fromPath(fieldName, imageFile.path));
                        }
                      }
                      final streamedResponse = await request.send();
                      final imageUpdateResponse = await http.Response.fromStream(streamedResponse);
                      if (imageUpdateResponse.statusCode != 200) throw Exception("이미지 URL 업데이트 실패: ${imageUpdateResponse.body}");

                      await _storage.write(key: 'character_id', value: newCharId.toString());
                      success = true;
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(pageContext).showSnackBar(SnackBar(content: Text('오류 발생: $e')));
                    } finally {
                      if (mounted) setState(() => _isUploading = false);
                    }
                    if (success) {
                      Provider.of<CharProvider>(pageContext, listen: false).setTemporaryImages(_images);
                      Navigator.of(pageContext).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const MenuPage()), (Route<dynamic> route) => false);
                    }
                  },
                ),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.petName}의 사진 등록', style: AppTextStyles.title.copyWith(fontSize: 24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primaryBrown),
      ),
      extendBodyBehindAppBar: true,
      body: ThemedBackground(
        child: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const SizedBox(height: 60), // Space for AppBar
                    Text('거의 다 됐어요!', style: AppTextStyles.title),
                    const SizedBox(height: 12),
                    Text('네 방향의 사진을 모두 등록해주세요', style: AppTextStyles.body),
                    const SizedBox(height: 36),
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 24,
                        mainAxisSpacing: 24,
                        children: _images.keys.map((String key) => _buildPhotoSlot(key)).toList(),
                      ),
                    ),
                    const SizedBox(height: 36),
                    _buildSubmitButton(),
                  ],
                ),
              ),
            ),
            if (_isUploading)
              Container(
                color: AppColors.background.withOpacity(0.7),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.primaryBrown),
                      const SizedBox(height: 24),
                      Text('사진을 등록하는 중...', style: AppTextStyles.title.copyWith(fontSize: 20)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSlot(String key) {
    XFile? image = _images[key];
    String label = _labels[key]!;
    return GestureDetector(
      onTap: () => _showImageSourceActionSheet(key),
      child: ClipRRect(
        borderRadius: AppDecorations.cardRadius,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppDecorations.cardRadius,
            boxShadow: AppDecorations.cardShadow,
          ),
          child: image == null
              ? CustomPaint(
                  painter: DashedBorderPainter(),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FaIcon(FontAwesomeIcons.cameraRetro, size: 40, color: AppColors.secondaryBrown.withOpacity(0.6)),
                        const SizedBox(height: 12),
                        Text(label, style: AppTextStyles.body.copyWith(fontSize: 18)),
                      ],
                    ),
                  ),
                )
              : (kIsWeb
                  ? Image.network(image.path, fit: BoxFit.cover, width: double.infinity, height: double.infinity, filterQuality: FilterQuality.high)
                  : Image.file(File(image.path), fit: BoxFit.cover, width: double.infinity, height: double.infinity, filterQuality: FilterQuality.high)),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    bool canSubmit = _areAllImagesSelected() && !_isUploading;
    return Container(
      decoration: BoxDecoration(
        boxShadow: canSubmit ? AppDecorations.cardShadow : null,
        borderRadius: AppDecorations.cardRadius,
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: canSubmit ? AppColors.primaryBrown : AppColors.statDef,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius),
          elevation: 0,
        ),
        onPressed: canSubmit ? _submit : null,
        child: Text('완료', style: AppTextStyles.button.copyWith(fontSize: 22)),
      ),
    );
  }
}

class DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.secondaryBrown.withOpacity(0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    Path path = Path();
    const double dashWidth = 8.0;
    const double dashSpace = 6.0;

    // Top border
    double startX = 0;
    while (startX < size.width) {
      path.moveTo(startX, 0);
      path.lineTo(startX + dashWidth, 0);
      startX += dashWidth + dashSpace;
    }

    // Right border
    double startY = 0;
    while (startY < size.height) {
      path.moveTo(size.width, startY);
      path.lineTo(size.width, startY + dashWidth);
      startY += dashWidth + dashSpace;
    }

    // Bottom border
    startX = 0;
    while (startX < size.width) {
      path.moveTo(startX, size.height);
      path.lineTo(startX + dashWidth, size.height);
      startX += dashWidth + dashSpace;
    }

    // Left border
    startY = 0;
    while (startY < size.height) {
      path.moveTo(0, startY);
      path.lineTo(0, startY + dashWidth);
      startY += dashWidth + dashSpace;
    }
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
