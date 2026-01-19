import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // --- 3D Choco Toy Palette ---
  
  // Background: Warm Cream (The Canvas)
  static const Color background = Color(0xFFFFF9E6); 
  
  // Primary: deep warm brown (The Choco)
  static const Color primary = Color(0xFF5D4037); 
  static const Color primaryDark = Color(0xFF3E2723); // For 3D Shadows
  
  // Secondary: Soft Salmon (The Highlight)
  static const Color secondary = Color(0xFFFFAB91); 
  static const Color secondaryDark = Color(0xFFD84315);
  
  // Accent: Soft Yellow/Orange (The Garnish)
  static const Color accent = Color(0xFFFFCC80);

  // Surface: Clean White
  static const Color surface = Colors.white; 
  
  // Text
  static const Color textMain = Color(0xFF3E2723); // Almost black brown
  static const Color textSub = Color(0xFF8D6E63);  // Muted brown
  
  // Outline
  static const Color stroke = Color(0xFF3E2723); // Deep Brown Stroke

  // Stats Colors (Pastel Choco)
  static const Color statRed = Color(0xFFFF8A80);
  static const Color statBlue = Color(0xFF80DEEA);
  static const Color statYellow = Color(0xFFFFE082);
  static const Color statGreen = Color(0xFFA5D6A7);
  static const Color statGrey = Color(0xFFB0BEC5);

  // Legacy mappings for compatibility
  static const Color white = Colors.white;
  static const Color textWhite = Colors.white;
  static const Color primaryMint = secondary; // Map old mint to secondary
  static const Color secondaryPink = statRed;
  static const Color danger = statRed;
  static const Color info = statBlue;
  static const Color success = statGreen;
  static const Color warning = statYellow;
  static const Color border = stroke;
  
  // Restored Legacy Aliases
  static const Color primaryBrown = primary;
  static const Color secondaryBrown = textSub;
  static const Color softCharcoal = textMain;
  static const Color neutral = textSub;
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: GoogleFonts.jua().fontFamily,
      
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        background: AppColors.background,
        surface: AppColors.surface,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        outline: AppColors.stroke, 
      ),

      // --- Button Theme (Choco 3D) ---
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 0, // Handled by custom widget usually
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.stroke, width: 3),
          ),
          textStyle: GoogleFonts.jua(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),

      // --- Card Theme (Chunky) ---
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: const BorderSide(color: AppColors.stroke, width: 3),
        ),
      ),
      
      // --- Text Theme ---
      textTheme: TextTheme(
        displayLarge: GoogleFonts.jua(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textMain),
        titleLarge: GoogleFonts.jua(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textMain),
        bodyLarge: GoogleFonts.jua(fontSize: 18, color: AppColors.textMain),
        bodyMedium: GoogleFonts.jua(fontSize: 16, color: AppColors.textSub),
      ),

      iconTheme: const IconThemeData(
        color: AppColors.textMain,
        size: 28,
      ),
    );
  }
}
