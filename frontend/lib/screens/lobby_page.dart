import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pet_trainer_frontend/config/theme.dart';

class LobbyPage extends StatelessWidget {
  final XFile frontImage;

  const LobbyPage({super.key, required this.frontImage});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamWhite,
      appBar: AppBar(
        title: const Text('로비'),
        automaticallyImplyLeading: false, // No back button
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Spacer(flex: 2),
            // Character Image
            Container(
              width: MediaQuery.of(context).size.width * 0.7,
              height: MediaQuery.of(context).size.width * 0.7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 2,
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20.0),
                child: kIsWeb
                    ? Image.network(
                        frontImage.path,
                        fit: BoxFit.cover,
                      )
                    : Image.file(
                        File(frontImage.path),
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const Spacer(flex: 1),
            // Menu Buttons
            _buildMenuButton(context, '훈련', () {
              // TODO: Navigate to Training Page
              print('Navigate to Training');
            }),
            const SizedBox(height: 16),
            _buildMenuButton(context, '마이룸', () {
              // TODO: Navigate to My Room Page
              print('Navigate to My Room');
            }),
            const SizedBox(height: 16),
            _buildMenuButton(context, '대전', () {
              // TODO: Navigate to Battle Page
              print('Navigate to Battle');
            }),
            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context, String title, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFD6A579), // Brown button color
        minimumSize: Size(MediaQuery.of(context).size.width * 0.6, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
      onPressed: onPressed,
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
