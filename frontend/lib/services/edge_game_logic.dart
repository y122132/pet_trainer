// Edge AI Game Logic
// 백엔드의 거리 판정 및 게임 로직을 프론트엔드로 이식
// Edge AI 모드에서 완전한 로컬 처리 구현

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pet_trainer_frontend/api_config.dart';

/// Pet별 Mode별 Target Props 정의
class EdgeGameConfig {
  // Mode별 거리 임계값
  static Map<String, Map<String, double>> minDistance = {
    'playing': {'easy': 0.25, 'hard': 0.15},
    'feeding': {'easy': 0.15, 'hard': 0.10},
    'interaction': {'easy': 0.30, 'hard': 0.20},
  };

  // Pet별 Mode별 Target Props
  static Map<int, Map<String, List<int>>> petBehaviors = {
    16: { // Dog
      'playing': [32, 29, 77, 39, 41], 
      'feeding': [45, 41, 39, 46, 47, 48, 49, 50, 51], 
      'interaction': [0],
    },
    // Defaults... (will be overwritten by server)
    15: { 'playing': [39, 41, 29], 'feeding': [45, 41], 'interaction': [0] },
    14: { 'playing': [32, 39, 41], 'feeding': [45], 'interaction': [0] },
  };

  // Mode별 Messages
  static Map<String, Map<String, String>> messages = {
    'playing': { 'success': '공놀이 중! 🎾', 'distance_fail': '장난감과 너무 멀어요', 'prop_missing': '장난감을 보여주세요' },
    'feeding': { 'success': '맛있는 식사 시간 🥣', 'distance_fail': '그릇 가까이 가야 해요!', 'prop_missing': '먹이를 보여주세요' },
    'interaction': { 'success': '주인과 교감 중 ❤️', 'distance_fail': '주인님과 더 가까이!', 'prop_missing': '함께 찍어주세요' },
  };
  
  // [NEW] Config Loader
  static Future<void> loadFromBackend() async {
      try {
        final url = Uri.parse("${AppConfig.baseUrl}/config/game_logic");
        final response = await http.get(url).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
            final data = jsonDecode(utf8.decode(response.bodyBytes));
            
            // 1. Min Distance
            if (data['detection_settings'] != null && data['detection_settings']['min_distance'] != null) {
                Map<String, dynamic> rawDist = data['detection_settings']['min_distance'];
                // Need deep copy / type conversion
                rawDist.forEach((mode, thresholds) {
                    if (minDistance.containsKey(mode) && thresholds is Map) {
                       minDistance[mode]!['easy'] = (thresholds['easy'] as num).toDouble();
                       minDistance[mode]!['hard'] = (thresholds['hard'] as num).toDouble();
                    }
                });
            }
            
            // 2. Pet Behaviors (Targets)
            if (data['pet_behaviors'] != null) {
                Map<String, dynamic> rawBeh = data['pet_behaviors'];
                rawBeh.forEach((petIdStr, config) {
                   int petId = int.tryParse(petIdStr) ?? 16;
                   
                   Map<String, List<int>> modeMap = {};
                   if (config is Map) {
                       config.forEach((mode, settings) {
                           if (settings is Map && settings['targets'] != null) {
                               modeMap[mode] = List<int>.from(settings['targets']);
                           }
                           // Messages could also be synced here if needed
                       });
                   }
                   petBehaviors[petId] = modeMap;
                });
            }
            print("[EdgeGameLogic] Config Synced with Server");
        }
      } catch (e) {
          print("[EdgeGameLogic] Config Sync Failed (Using Defaults): $e");
      }
  }
}

/// Aspect ratio를 고려한 시각적 거리의 제곱을 계산
double calculateSquaredDistance(
  List<double> p1,
  List<double> p2,
  double xScale,
  double yScale,
) {
  final dx = (p1[0] - p2[0]) * xScale;
  final dy = (p1[1] - p2[1]) * yScale;
  return dx * dx + dy * dy;
}

/// Edge AI Detection 결과를 바탕으로 게임 로직 수행
class EdgeGameLogic {
  /// 게임 판정 수행
  static Map<String, dynamic> processGameLogic({
    required List<dynamic> bbox,
    required String mode,
    required int targetClassId,
    required String difficulty,
    required double imageWidth,
    required double imageHeight,
    List<dynamic>? petKeypoints,
  }) {
    // 기본 응답
    final result = <String, dynamic>{
      'status': 'detecting',
      'feedback': '',
      'is_specific_feedback': false,
    };

    // Aspect ratio 계산
    final aspectRatio = imageWidth / imageHeight;
    final double xScale, yScale;
    if (aspectRatio > 1.0) {
      xScale = aspectRatio;
      yScale = 1.0;
    } else {
      xScale = 1.0;
      yScale = 1.0 / aspectRatio;
    }

    // 1. Parse Detections
    final propBoxes = <int, List<double>>{};
    List<double>? petBox;
    double petConf = 0.0;
    List<double>? petNose;
    final List<List<double>> petPaws = [];

    // Target Props 가져오기
    final petConfig = EdgeGameConfig.petBehaviors[targetClassId] ?? 
                      EdgeGameConfig.petBehaviors[16]!; // Default: Dog (Safe: always exists)
    final targetProps = petConfig[mode] ?? [];

    for (var obj in bbox) {
      if (obj is! List || obj.length < 6) continue;

      final box = [obj[0] as double, obj[1] as double, obj[2] as double, obj[3] as double];
      final conf = (obj[4] as num).toDouble();
      final clsId = (obj[5] as num).toInt();

      // Pet Check (Dog 16, Cat 15, Bird 14)
      if (clsId == targetClassId || (targetClassId == -1 && [14, 15, 16].contains(clsId))) {
        if (conf > petConf) {
          petConf = conf;
          petBox = [...box, conf, clsId.toDouble()];
        }
      }
      // Human (0) or Other Props
      else if (clsId == 0 || targetProps.contains(clsId)) {
        if (!propBoxes.containsKey(clsId) || conf > propBoxes[clsId]![4]) {
          propBoxes[clsId] = [...box, conf, clsId.toDouble()];
        }
      }
    }

    // 2. Extract Pet Keypoints (Nose, Paws)
    if (petKeypoints != null && petKeypoints.isNotEmpty) {
      // TrainingController now provides STRUCTURED keypoints: [[x,y,c], [x,y,c], ...] (17 points)
      // We process only the provided points (already filtered for primary pet)
      
      final kpts = petKeypoints; // List<List<dynamic>>
      
      if (kpts.length >= 17) { // Ensure we have enough points
          // Nose (Index 0 in COCO)
          if (kpts[0].length >= 3) {
             final nx = (kpts[0][0] as num).toDouble();
             final ny = (kpts[0][1] as num).toDouble();
             final nc = (kpts[0][2] as num).toDouble();
             if (nc > 0.5) petNose = [nx, ny];
          }
          
          // Paws (Indices 9, 10 - Front Left, Front Right)
          for (int idx in [9, 10]) {
             if (kpts[idx].length >= 3) {
                 final px = (kpts[idx][0] as num).toDouble();
                 final py = (kpts[idx][1] as num).toDouble();
                 final pc = (kpts[idx][2] as num).toDouble();
                 if (pc > 0.3) petPaws.add([px, py]);
             }
          }
      }
    }

    // CASE 1: Pet 미발견
    if (petBox == null) {
      final hasProp = propBoxes.isNotEmpty;
      result['status'] = 'detecting';
      result['feedback'] = hasProp 
          ? EdgeGameConfig.messages[mode]!['prop_missing']! 
          : '반려동물 찾는 중...';
      result['is_specific_feedback'] = hasProp;
      return result;
    }

    // CASE 2: Pet 발견, Target Prop 확인
    final hasTarget = targetProps.any((id) => propBoxes.containsKey(id));
    
    if (!hasTarget) {
      result['status'] = 'stay';
      result['feedback'] = EdgeGameConfig.messages[mode]!['prop_missing']!;
      result['is_specific_feedback'] = true;
      return result;
    }

    // 3. 거리 계산
    double minDistSq = 9999.0;

    // Source Points (Pet)
    final srcPoints = <List<double>>[];
    if (petNose != null) srcPoints.add(petNose);
    if (mode == 'playing' && petPaws.isNotEmpty) srcPoints.addAll(petPaws);

    // Fallback: BBox Center
    if (srcPoints.isEmpty) {
      final cx = (petBox[0] + petBox[2]) / 2;
      final cy = (petBox[1] + petBox[3]) / 2;
      srcPoints.add([cx, cy]);
    }

    // Calculate distance to each target prop
    for (final propId in targetProps) {
      if (!propBoxes.containsKey(propId)) continue;

      final propBox = propBoxes[propId]!;
      final targetCx = (propBox[0] + propBox[2]) / 2;
      final targetCy = (propBox[1] + propBox[3]) / 2;

      for (final sp in srcPoints) {
        final distSq = calculateSquaredDistance(sp, [targetCx, targetCy], xScale, yScale);
        if (distSq < minDistSq) minDistSq = distSq;
      }
    }

    // 4. 거리 임계값 판정
    final minDistSettings = EdgeGameConfig.minDistance[mode] ?? {'easy': 0.25};
    final minDist = minDistSettings[difficulty] ?? minDistSettings['easy']!;
    final isInteracting = minDistSq < (minDist * minDist);

    if (isInteracting) {
      result['status'] = 'success';
      result['feedback'] = EdgeGameConfig.messages[mode]!['success']!;
      result['is_specific_feedback'] = true;
    } else {
      result['status'] = 'stay';
      result['feedback'] = EdgeGameConfig.messages[mode]!['distance_fail']!;
      result['is_specific_feedback'] = true;
    }

    return result;
  }
}
