import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:pet_trainer_frontend/api_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'menu_page.dart';

class SimpleCharCreatePage extends StatefulWidget {
  const SimpleCharCreatePage({super.key});

  @override
  State<SimpleCharCreatePage> createState() => _SimpleCharCreatePageState();
}

class _SimpleCharCreatePageState extends State<SimpleCharCreatePage> {
  final _nameController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  bool _isLoading = false;

  Future<void> _createCharacter() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("캐릭터 이름을 입력해주세요.")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final token = await _storage.read(key: 'jwt_token');
      final userId = await _storage.read(key: 'user_id');

      if (token == null || userId == null) {
        throw Exception("로그인 정보가 없습니다.");
      }

      // API 호출
      // backend/app/api/v1/characters.py: create_character
      print("[DEBUG] Sending Create Request: user_id=$userId, name=${_nameController.text}");

      final response = await http.post(
        Uri.parse("${AppConfig.charactersUrl}/"),  // AppConfig.charactersUrl 사용 (/v1 포함됨) 
        headers: {
          "Content-Type": "application/json; charset=UTF-8", // UTF-8 명시
          "Authorization": "Bearer $token"
        },
        body: jsonEncode({
          "user_id": int.parse(userId),
          "name": _nameController.text,
        }),
      );

      print("[DEBUG] Response Status: ${response.statusCode}");
      print("[DEBUG] Response Body: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return;
        if (!mounted) return;
        
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        final createdId = responseData['id'];

        if (createdId != null) {
          await _storage.write(key: 'character_id', value: createdId.toString());
          print("[Create] 캐릭터 ID 저장 완료: $createdId");
        }

        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text("캐릭터가 생성되었습니다!"))
        );
        // 생성 성공 시 바로 메인으로 이동
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MenuPage()),
        );
      } else {
        throw Exception("캐릭터 생성 실패 (${response.statusCode}): ${utf8.decode(response.bodyBytes)}");
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("오류 발생: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("캐릭터 생성")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.pets, size: 80, color: Colors.brown),
            const SizedBox(height: 20),
            const Text(
              "함께할 반려동물의 이름을 지어주세요!",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "캐릭터 이름",
                border: OutlineInputBorder(),
                hintText: "예: 멍멍이, 해피",
              ),
            ),
            const SizedBox(height: 30),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _createCharacter,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text("시작하기", style: TextStyle(fontSize: 18)),
                  ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
