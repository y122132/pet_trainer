import 'package:flutter/material.dart';

class AppColors {
  // Main Palette
  static const Color navy = Color(0xFF2E3A59);
  static const Color cyberYellow = Color(0xFFFFD700); 
  static const Color spaceBlack = Color(0xFF1E2742);
  static const Color background = Color(0xFFF5F5FA);
  
  // Semantic
  static const Color success = Color(0xFF00E676);
  static const Color danger = Color(0xFFFF1744);
  static const Color neutral = Colors.grey;
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      
      // Color Scheme
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.navy,
        primary: AppColors.navy,
        secondary: AppColors.cyberYellow,
        surface: Colors.white,
        background: AppColors.background,
      ),

      // AppBar Theme
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.navy,
          fontSize: 20,
          fontWeight: FontWeight.w900, // Black Han Sans style
          letterSpacing: 1.0,
        ),
        iconTheme: IconThemeData(color: AppColors.navy),
      ),

      // Button Themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: AppColors.navy.withOpacity(0.4),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 8,
        shadowColor: Colors.black.withOpacity(0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      ),

      // Text Theme (Using default font for now, can create custom TextStyle later)
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w900,
          fontSize: 32,
        ),
        titleLarge: TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
        bodyLarge: TextStyle(
          color: Color(0xFF4A5568),
          fontSize: 16,
        ),
      ),

      // Page Transitions
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
