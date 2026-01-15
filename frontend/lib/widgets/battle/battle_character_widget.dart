import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui'; // For ImageFilter
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import 'package:pet_trainer_frontend/api_config.dart'; // [New]

// --- NEW WIDGETS ---

class BattleAvatarWidget extends StatelessWidget {
  final String petType;
  final double damageOpacity;
  final Animation<double> idleAnimation;
  final double size;

  // New image properties
  final String imageType; // 'front', 'back', 'side', 'face'
  final String? frontUrl, backUrl, sideUrl, faceUrl;
  final String? customImagePath;
  final XFile? tempFrontImage, tempBackImage, tempSideImage, tempFaceImage;


  const BattleAvatarWidget({
    super.key,
    required this.petType,
    required this.idleAnimation,
    required this.imageType,
    this.damageOpacity = 0.0,
    this.size = 160,
    this.frontUrl,
    this.backUrl,
    this.sideUrl,
    this.faceUrl,
    this.customImagePath,
    this.tempFrontImage,
    this.tempBackImage,
    this.tempSideImage,
    this.tempFaceImage,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 1. Circular Frame (MyRoom Style)
        ScaleTransition(
          scale: idleAnimation,
          alignment: Alignment.center,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.8), // Softer look
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                color: Colors.white,
                width: size * 0.03, // Responsive border width
              ),
            ),
            child: ClipOval(
              child: _buildCharImage(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCharImage() {
    XFile? tempImage;
    String? remoteUrl;
    
    if (customImagePath != null && customImagePath!.isNotEmpty) {
      return Image.asset(customImagePath!, height: size, fit: BoxFit.contain);
    }
    
    switch (imageType) {
      case 'front':
        tempImage = tempFrontImage;
        remoteUrl = frontUrl;
        break;
      case 'back':
        tempImage = tempBackImage;
        remoteUrl = backUrl;
        break;
      case 'side':
        tempImage = tempSideImage;
        remoteUrl = sideUrl;
        break;
      case 'face':
        tempImage = tempFaceImage;
        remoteUrl = faceUrl;
        break;
    }

    Widget imageWidget;

    if (tempImage != null) {
      imageWidget = kIsWeb
          ? Image.network(tempImage.path, height: size, fit: BoxFit.contain)
          : Image.file(File(tempImage.path), height: size, fit: BoxFit.contain);
    } else if (remoteUrl != null && remoteUrl.isNotEmpty) {
      // [Fix] 상대 경로 및 localhost 레거시 처리
      String finalUrl = remoteUrl;
      if (finalUrl.startsWith('/')) {
        finalUrl = "${AppConfig.serverBaseUrl}$finalUrl";
      } else if (finalUrl.contains('localhost')) {
        finalUrl = finalUrl.replaceFirst('localhost', AppConfig.serverIp);
      }
      imageWidget = Image.network(finalUrl, height: size, fit: BoxFit.contain);
    } else {
      imageWidget = Image.asset(_getAssetPath(petType), height: size, fit: BoxFit.contain);
    }

    return Stack(
      children: [
        imageWidget,
        AnimatedOpacity(
          opacity: damageOpacity,
          duration: const Duration(milliseconds: 100),
          child: imageWidget, // This doesn't work for non-asset images, needs fix
        )
      ],
    );
  }
  
  String _getAssetPath(String petType) {
    switch (petType.toLowerCase()) {
      case 'dog': return "assets/images/characters/멜빵옷.png";
      case 'cat': return "assets/images/characters/공주옷.png";
      case 'banana': return "assets/images/characters/바나나옷.png";
      case 'ninja': return "assets/images/characters/닌자옷.png";
      default: return "assets/images/characters/닌자옷.png"; 
    }
  }
}

class BattleHudWidget extends StatelessWidget {
  final String name;
  final int hp;
  final int maxHp;
  final bool isMe;
  final bool isThinking;
  final List<String> statuses;

  const BattleHudWidget({
    super.key,
    required this.name,
    required this.hp,
    required this.maxHp,
    required this.isMe, // Defines alignment
    this.isThinking = false,
    this.statuses = const [],
  });

  @override
  Widget build(BuildContext context) {
    // Glassmorphism HUD
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(isMe ? 0 : 20),
        topRight: Radius.circular(isMe ? 20 : 0),
        bottomRight: Radius.circular(isMe ? 20 : 0),
        bottomLeft: Radius.circular(isMe ? 0 : 20),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isMe ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.4),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: isMe 
                ? [Colors.white.withOpacity(0.2), Colors.white.withOpacity(0.05)]
                : [Colors.black.withOpacity(0.5), Colors.black.withOpacity(0.2)]
            )
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Name & Thinking
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  if (isThinking) ...[
                     const SizedBox(width: 8),
                     const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.yellowAccent)))
                  ]
                ],
              ),
              const SizedBox(height: 6),
              
              // HP Bar
              _buildHpBar(hp, maxHp),
              const SizedBox(height: 4),
              Text("$hp / $maxHp", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w500)),

              // Buffs
              if (statuses.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  alignment: isMe ? WrapAlignment.start : WrapAlignment.end,
                  children: statuses.map((s) => _buildStatusChip(s)).toList(),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _getStatusColor(label).withOpacity(0.8),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white30, width: 0.5)
      ),
      child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
  
  Color _getStatusColor(String status) {
    if (status.contains('poison')) return Colors.purple;
    if (status.contains('burn')) return Colors.red;
    if (status.contains('paral')) return Colors.yellow[700]!;
    if (status.contains('sleep')) return Colors.grey;
    if (status.contains('reco')) return Colors.green; // Heal/Recover
    return Colors.blueGrey;
  }

  Widget _buildHpBar(int current, int max) {
    double pct = (max == 0) ? 0 : (current / max).clamp(0.0, 1.0);
    return SizedBox(
      width: 140, // Wider bar
      height: 10,  // Thicker bar
      child: Stack(
        children: [
          // Background
          Container(decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(5))),
          // Fill
          AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            widthFactor: pct,
            child: Container(
               decoration: BoxDecoration(
                 gradient: LinearGradient(colors: [_getHpColor(pct).withOpacity(0.6), _getHpColor(pct)]),
                 borderRadius: BorderRadius.circular(5),
                 boxShadow: [BoxShadow(color: _getHpColor(pct).withOpacity(0.5), blurRadius: 6)]
               ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getHpColor(double pct) {
    if (pct > 0.5) return Colors.greenAccent;
    if (pct > 0.2) return Colors.amber;
    return Colors.redAccent;
  }
}


// --- COMPATAIBILITY WRAPPER (DEPRECATED) ---

class BattleCharacterWidget extends StatelessWidget {
  final String name;
  final int hp;
  final int maxHp;
  final String petType;
  final bool isMe;
  final double damageOpacity;
  final bool isThinking;
  final List<String> statuses;
  final Animation<double> idleAnimation;

  // New image properties
  final String imageType; // 'front', 'back', 'side', 'face'
  final String? frontUrl, backUrl, sideUrl, faceUrl, customImagePath;
  final XFile? tempFrontImage, tempBackImage, tempSideImage, tempFaceImage;

  const BattleCharacterWidget({
    super.key,
    required this.name,
    required this.hp,
    required this.maxHp,
    required this.petType,
    required this.isMe,
    required this.idleAnimation,
    required this.imageType,
    this.damageOpacity = 0.0,
    this.isThinking = false,
    this.statuses = const [],
    this.frontUrl, 
    this.backUrl, 
    this.sideUrl, 
    this.faceUrl,
    this.customImagePath,
    this.tempFrontImage,
    this.tempBackImage,
    this.tempSideImage,
    this.tempFaceImage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BattleHudWidget(name: name, hp: hp, maxHp: maxHp, isMe: isMe, isThinking: isThinking, statuses: statuses),
        const SizedBox(height: 10),
        BattleAvatarWidget(
          petType: petType, 
          idleAnimation: idleAnimation, 
          damageOpacity: damageOpacity,
          imageType: imageType,
          frontUrl: frontUrl,
          backUrl: backUrl,
          sideUrl: sideUrl,
          faceUrl: faceUrl,
          customImagePath: customImagePath,
          tempFrontImage: tempFrontImage,
          tempBackImage: tempBackImage,
          tempSideImage: tempSideImage,
          tempFaceImage: tempFaceImage,
        ),
      ],
    );
  }
}
