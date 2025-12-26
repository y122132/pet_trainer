import 'dart:async';
import 'dart:convert';
import 'package:pet_trainer_frontend/models/battle_state.dart';

class BattleAnimationManager {
  final StreamController<BattleEvent> _eventController = StreamController<BattleEvent>.broadcast();
  Stream<BattleEvent> get eventStream => _eventController.stream;

  final Map<String, dynamic> skillData;

  BattleAnimationManager({required this.skillData});

  void emitEvent(BattleEvent event) {
    _eventController.add(event);
  }

  void dispose() {
    _eventController.close();
  }

  Future<void> processTurnResult(
    List<dynamic> results, 
    int myId, 
    String oppName,
    int? opponentId,
    Function(String) addLog, 
    Function(int, int) handleHpChange
  ) async {
    
    for (var res in results) {
       await Future.delayed(const Duration(milliseconds: 600));
       
       String type = res['type'] ?? 'unknown';
       if (type == 'turn_event') {
          String eventType = res['event_type'] ?? '';
          
          if (eventType == 'attack_start') {
              int attacker = res['attacker'];
              int moveId = res['move_id'];
              
              String moveName = "Unknown Move";
              // Lookup from dynamic JSON data
              if (skillData.containsKey(moveId.toString())) {
                moveName = skillData[moveId.toString()]['name'];
              } else if (skillData.containsKey(moveId)) { // in case int key
                 moveName = skillData[moveId]['name'];
              }

              String moveType = res['move_type'] ?? 'normal';
              String attackerName = (attacker == myId) ? "You" : oppName;

              addLog("$attackerName used $moveName!");
              
              if (moveType == 'heal' || moveType == 'evade' || moveType == 'stat_change') {
                 // Buff Animation
              } else {
                 // Dash/Attack Animation Trigger
                 _eventController.add(BattleEvent(type: BattleEventType.attack, actorId: attacker));
                 await Future.delayed(const Duration(milliseconds: 500));
              }

          } else if (eventType == 'hit_result') {
              String result = res['result'];
              if (result == 'miss') {
                 int target = res['defender'] ?? (opponentId); // Fallback
                 _eventController.add(BattleEvent(type: BattleEventType.miss, targetId: target));
                 addLog("Missed!");
              } else {
                 int target = res['defender'] ?? (opponentId);
                 int damage = res['damage'] ?? 0;
                 
                 if (damage > 0) {
                     _eventController.add(BattleEvent(type: BattleEventType.shake, targetId: target));
                     _eventController.add(BattleEvent(type: BattleEventType.damage, targetId: target, value: damage));
                     handleHpChange(target, -damage);
                 }

                 if (res['is_critical'] == true) {
                    _eventController.add(BattleEvent(type: BattleEventType.crit, targetId: target));
                    addLog("CRITICAL HIT!");
                 }
                 if (res['message'] != null) addLog(res['message']);
              }
              await Future.delayed(const Duration(milliseconds: 500));

          } else if (eventType == 'damage_apply') {
              int target = res['target'];
              int damage = res['damage'];
              
              if (damage > 0) {
                 _eventController.add(BattleEvent(type: BattleEventType.shake, targetId: target));
                 _eventController.add(BattleEvent(type: BattleEventType.damage, targetId: target, value: damage));

                 handleHpChange(target, -damage);

                 if (target == myId) {
                   addLog("Ouch! Took $damage damage!");
                 } else {
                   addLog("Hit! Dealt $damage damage!");
                 }
                 await Future.delayed(const Duration(milliseconds: 600));
              }

          } else if (res['message'] != null) {
              addLog(res['message']);
          }
       } else if (type == 'heal') {
           int target = _resolveTarget(res, myId, opponentId);
           int amount = res['value'] ?? 0;
           
           handleHpChange(target, amount);
           _eventController.add(BattleEvent(type: BattleEventType.heal, targetId: target, value: amount));
           
           if (res['message'] != null) addLog(res['message']);
           else addLog("Recovered $amount HP!");
           
           await Future.delayed(const Duration(milliseconds: 500));

       } else if (type == 'status_damage') {
           int target = res['target'] ?? myId; 
           int damage = res['damage'] ?? 0;
           String msg = res['message'] ?? "Took damage from status!";
           
           addLog(msg);
           
           if (damage > 0) {
               _eventController.add(BattleEvent(type: BattleEventType.shake, targetId: target));
               _eventController.add(BattleEvent(type: BattleEventType.damage, targetId: target, value: damage));
               handleHpChange(target, -damage);
               await Future.delayed(const Duration(milliseconds: 600));
           }

       } else if (type == 'status_recover') {
           String msg = res['message'] ?? "Recovered from status!";
           addLog(msg);
           await Future.delayed(const Duration(milliseconds: 500));
       }
    }
  }

  int _resolveTarget(Map<String, dynamic> res, int myId, int? opponentId) {
      var targetRaw = res['target'];
      if (targetRaw == 'self') return (res['attacker'] as int?) ?? myId;
      if (targetRaw == 'enemy') return (res['defender'] as int?) ?? opponentId ?? myId;
      if (targetRaw is int) return targetRaw;
      return myId;
  }
}
