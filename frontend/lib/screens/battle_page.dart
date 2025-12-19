import 'package:flutter/material.dart';

class BattlePage extends StatelessWidget {
  const BattlePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('전투', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Opacity(
               opacity: 0.5,
               child: Image.asset("assets/images/characters/돌.png", width: 200), // Placeholder image
             ),
             const SizedBox(height: 20),
             const Text("⚔️ 준비 중입니다 ⚔️", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey)),
             const SizedBox(height: 10),
             const Text("더 강력한 몬스터들이 몰려옵니다...", style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
