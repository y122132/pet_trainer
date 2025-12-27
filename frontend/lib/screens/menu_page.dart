import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'my_room_page.dart';
import 'mode_select_page.dart';
import 'battle_page.dart';
import 'user_list_screen.dart'; // [New]
import '../providers/char_provider.dart';
import '../config/theme.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> with SingleTickerProviderStateMixin {
  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));
    _breathingAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );
    _breathingController.repeat(reverse: true);
    
    // Auto-fetch data if not present
    WidgetsBinding.instance.addPostFrameCallback((_) {
        final provider = Provider.of<CharProvider>(context, listen: false);
        // 이미 데이터가 있다면 굳이 또 부를 필요 없지만, 최신화 위해 호출 가능
        provider.fetchMyCharacter();
    });
  }

  @override
  void dispose() {
    _breathingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Background Decor (Subtle Circles)
          Positioned(
            top: -100,
            right: -100,
            child: _buildDecorCircle(300, AppColors.navy.withOpacity(0.05)),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: _buildDecorCircle(200, AppColors.cyberYellow.withOpacity(0.1)),
          ),

          // 2. Main Character (Center - Lobby Style)
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 50), // Header Offset
                Expanded(
                  child: Consumer<CharProvider>(
                    builder: (context, provider, child) {
                      final imagePath = provider.character?.imageUrl ?? 
                                      'assets/images/characters/닌자옷.png';
                      
                      return AnimatedBuilder(
                        animation: _breathingAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _breathingAnimation.value,
                            child: child,
                          );
                        },
                        child: GestureDetector(
                           onTap: () {
                              // Simple interaction feedback
                              provider.updateStatusMessage("오늘도 훈련하러 가볼까요? 멍!");
                           },
                           child: Image.asset(imagePath, fit: BoxFit.contain),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 180), // Space for Bottom Menu
              ],
            ),
          ),

          // 3. UI Overlay - Header (User Info)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                     // User Profile Badge
                     Consumer<CharProvider>(
                       builder: (context, provider, child) {
                         String name = provider.character?.name ?? "트레이너";
                         String type = provider.character?.petType ?? "";
                         return Container(
                           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                           decoration: BoxDecoration(
                             color: Colors.white,
                             borderRadius: BorderRadius.circular(30),
                             boxShadow: [
                               BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, 4))
                             ]
                           ),
                           child: Row(
                             children: [
                               CircleAvatar(
                                 radius: 14,
                                 backgroundColor: AppColors.navy,
                                 child: const Icon(Icons.person, size: 16, color: Colors.white),
                               ),
                               const SizedBox(width: 8),
                               Text("$name ($type)", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy)),
                             ],
                           ),
                         );
                       },
                     ),
                     // Login/Switch User Buttons (Minified for Lobby)
                     Row(
                       children: [
                         _buildMiniUserButton(context, 1, Colors.blue),
                         const SizedBox(width: 8),
                         _buildMiniUserButton(context, 2, Colors.pink),
                       ],
                     )
                  ],
                ),
              ),
            ),
          ),
          
          // 4. UI Overlay - Bottom Menu (Action Cards)
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
               children: [
                 // Primary Action
                 _buildLobbyCard(
                   context,
                   title: "TRAINING",
                   subtitle: "스탯을 성장시키세요",
                   icon: Icons.fitness_center,
                   color: AppColors.navy,
                   onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ModeSelectPage())),
                   isPrimary: true,
                 ),
                 const SizedBox(height: 12),
                 // Secondary Row
                 Row(
                   children: [
                     Expanded(
                       child: _buildLobbyCard(
                         context,
                         title: "MY ROOM",
                         subtitle: "휴식 & 상태",
                         icon: Icons.home_rounded,
                         color: Colors.orangeAccent,
                         onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MyRoomPage())),
                       ),
                     ),
                     const SizedBox(width: 8),
                     // Friends Button [New]
                     Expanded(
                       child: _buildLobbyCard(
                         context,
                         title: "FRIENDS",
                         subtitle: "채팅",
                         icon: Icons.people_alt_rounded,
                         color: Colors.teal,
                         onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const UserListScreen())),
                       ),
                     ),
                     const SizedBox(width: 8),
                     Expanded(
                       child: _buildLobbyCard(
                         context,
                         title: "BATTLE",
                         subtitle: "실전 대결",
                         icon: Icons.sports_kabaddi_rounded, 
                         color: AppColors.danger,
                         onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BattlePage())),
                       ),
                     ),
                   ],
                 )
               ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecorCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildMiniUserButton(BuildContext context, int id, Color color) {
    return GestureDetector(
      onTap: () => Provider.of<CharProvider>(context, listen: false).fetchCharacter(id),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
        child: Text("U$id", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
      ),
    );
  }

  Widget _buildLobbyCard(BuildContext context, {
    required String title, required String subtitle, required IconData icon, 
    required Color color, required VoidCallback onTap, bool isPrimary = false
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: isPrimary ? 90 : 110,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 6))
          ],
          border: isPrimary ? Border.all(color: color, width: 2) : null,
        ),
        child: isPrimary 
          ? Row( // Horizontal Layout for Primary
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: color, letterSpacing: 1.0)),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
                const Spacer(),
                Icon(Icons.arrow_forward_ios_rounded, color: color.withOpacity(0.5), size: 18)
              ],
            )
          : Column( // Vertical Layout for Secondary
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                 Icon(icon, color: color, size: 32),
                 const SizedBox(height: 8),
                 Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
              ],
            ),
      ),
    );
  }
}
