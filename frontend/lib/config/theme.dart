import 'package:flutter/material.dart';

class AppColors {
  // Cute Pastel Palette
  static const Color primaryMint = Color(0xFFA0E7E5);   // Soft Mint
  static const Color secondaryPink = Color(0xFFFFAEBC); // Warm Pink
  static const Color accentYellow = Color(0xFFFBE7C6);  // Lemon Yellow
  static const Color creamWhite = Color(0xFFFFFDF9);    // Creamy Background
  static const Color softCharcoal = Color(0xFF4A4A4A);  // Soft Text
  
  // Semantic
  static const Color success = Color(0xFFB4F8C8); // Pastel Green
  static const Color danger = Color(0xFFFFAEBC);  // Pastel Red (Pinkish)
  static const Color neutral = Color(0xFFE0E0E0);
  
  // Legacy aliases for compatibility (mapping to new palette)
  static const Color navy = softCharcoal;
  static const Color cyberYellow = accentYellow;
  static const Color spaceBlack = softCharcoal;
  static const Color background = creamWhite;
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.creamWhite,
      
      // Color Scheme
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryMint,
        primary: AppColors.primaryMint,
        secondary: AppColors.secondaryPink,
        tertiary: AppColors.accentYellow,
        surface: Colors.white,
        background: AppColors.creamWhite,
        error: AppColors.danger,
      ),

      // AppBar Theme
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.softCharcoal,
          fontSize: 24,
          fontWeight: FontWeight.w900, 
          letterSpacing: 0.5,
          fontFamily: 'RoundFont', // Generic placeholder if font added later
        ),
        iconTheme: IconThemeData(color: AppColors.softCharcoal),
      ),

      // Button Themes (Rounded & Puffy)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryMint,
          foregroundColor: AppColors.softCharcoal,
          elevation: 0, // Flat look with shadow handled by shape/container usually in cute UI
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // Card Theme (Soft Shadow & Round)
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 8,
        shadowColor: AppColors.primaryMint.withOpacity(0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
      
      // Floating Action Button
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.secondaryPink,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: CircleBorder(), 
      ),
      
      // Input Decoration (Round Text Fields)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: AppColors.neutral, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: AppColors.primaryMint, width: 2),
        ),
      ),

      // Text Theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: AppColors.softCharcoal, fontWeight: FontWeight.w900, fontSize: 32),
        titleLarge: TextStyle(color: AppColors.softCharcoal, fontWeight: FontWeight.bold, fontSize: 20),
        bodyLarge: TextStyle(color: AppColors.softCharcoal, fontSize: 16),
        bodyMedium: TextStyle(color: AppColors.softCharcoal, fontSize: 14),
      ),
    );
  }
}
