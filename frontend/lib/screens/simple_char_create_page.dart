import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pet_trainer_frontend/screens/pet_photo_reg_page.dart';
import '../config/design_system.dart';

class SimpleCharCreatePage extends StatefulWidget {
  const SimpleCharCreatePage({super.key});

  @override
  State<SimpleCharCreatePage> createState() => _SimpleCharCreatePageState();
}

class _SimpleCharCreatePageState extends State<SimpleCharCreatePage> {
  final _nameController = TextEditingController();

  void _navigateToPhotoRegistration() {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("캐릭터 이름을 입력해주세요.", style: AppTextStyles.button),
          backgroundColor: Colors.redAccent,
          shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            PetPhotoRegistrationPage(petName: _nameController.text),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.primaryBrown),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: ThemedBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Image.asset(
                  'assets/images/독고 표지 이름.png',
                  width: MediaQuery.of(context).size.width * 0.5,
                  filterQuality: FilterQuality.high,
                ),
                const SizedBox(height: 30),
                Text(
                  '나만의 반려견 만들기',
                  style: AppTextStyles.title,
                ),
                const SizedBox(height: 60),
                _buildTextField(
                  controller: _nameController,
                  hintText: "캐릭터 이름",
                  icon: Icons.pets,
                ),
                const SizedBox(height: 30),
                _buildSubmitButton(),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: AppDecorations.cardShadow,
        borderRadius: AppDecorations.cardRadius,
      ),
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        style: AppTextStyles.base.copyWith(fontSize: 18),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTextStyles.body,
          prefixIcon: Icon(icon, color: AppColors.secondaryBrown, size: 28),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 22, horizontal: 25),
          border: OutlineInputBorder(
            borderRadius: AppDecorations.cardRadius,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppDecorations.cardRadius,
            borderSide:
                const BorderSide(color: AppColors.primaryBrown, width: 2.5),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: AppDecorations.cardShadow,
        borderRadius: AppDecorations.cardRadius,
      ),
      child: ElevatedButton.icon(
        onPressed: _navigateToPhotoRegistration,
        icon: const Icon(Icons.check, color: Colors.white, size: 28),
        label: Text('다음', style: AppTextStyles.button.copyWith(fontSize: 22)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBrown,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius),
          elevation: 0,
        ),
      ),
    );
  }
}
