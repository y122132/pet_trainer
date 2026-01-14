import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // --- Core Palette (Warm Brown & Cream) ---
  // Primary: Deep, rich brown for buttons and strong accents
  static const Color primary = Color(0xFF5D4037);    // Deep Warm Brown
  
  // Secondary: Soft salmon/clay for highlights and softer actions
  static const Color secondary = Color(0xFFFFAB91);  // Soft Salmon
  
  // Background: Warm, cozy cream
  static const Color background = Color(0xFFFFF9E6); // Warm Cream
  
  // Surface: Clean white for cards
  static const Color surface = Color(0xFFFFFFFF);    // White
  
  // Accents
  static const Color accent = Color(0xFFFFCC80);     // Soft Orange/Peach

  // --- Semantic Colors (Softened) ---
  static const Color success = Color(0xFFA5D6A7);    // Soft Green
  static const Color warning = Color(0xFFFFE082);    // Soft Amber
  static const Color danger = Color(0xFFEF9A9A);     // Soft Red
  static const Color info = Color(0xFF90CAF9);       // Soft Blue

  // --- Neutrals ---
  static const Color textMain = Color(0xFF4E342E);   // Dark Brown (almost black)
  static const Color textSub = Color(0xFF8D6E63);    // Medium Brown
  static const Color border = Color(0xFFD7CCC8);     // Light Brown Border
  static const Color white = Colors.white;
  
  // --- Legacy Compatibility (Mapped to New Warm Palette) ---
  static const Color primaryMint = Color(0xFF88E3E0); // Kept for legacy reference but discouraged
  static const Color secondaryPink = secondary;
  static const Color accentYellow = accent;
  static const Color softBlue = info;
  
  static const Color softCharcoal = textMain;
  static const Color creamWhite = background; // Direct mapping
  
  // Mapping old aliases
  static const Color primaryBrown = primary;   
  static const Color secondaryBrown = textSub;     
  static const Color neutral = textSub;            
  static const Color navy = textMain;              
  static const Color cyberYellow = accent;   
  
  // Legacy Stat Colors
  static const Color statStr = danger;   
  static const Color statInt = info;     
  static const Color statDex = success;  
  static const Color statDef = warning;  
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: GoogleFonts.jua().fontFamily, // Cute Font

      // Color Scheme
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.accent,
        surface: AppColors.surface,
        background: AppColors.background,
        error: AppColors.danger,
        onPrimary: AppColors.white,
        onSecondary: AppColors.white,
        onSurface: AppColors.textMain,
      ),

      // AppBar Theme
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.jua(
          color: AppColors.textMain,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: AppColors.textMain),
      ),

      // ElevatedButton Theme (Warm & Round)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 4,
          shadowColor: AppColors.primary.withOpacity(0.3),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: GoogleFonts.jua(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // Card Theme (Soft & Clean)
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 4,
        shadowColor: AppColors.primary.withOpacity(0.1),
        surfaceTintColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.textSub),
        hintStyle: const TextStyle(color: AppColors.textSub),
      ),
      
      // Text Theme
      textTheme: TextTheme(
        displayLarge: GoogleFonts.jua(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textMain),
        titleLarge: GoogleFonts.jua(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textMain),
        bodyLarge: GoogleFonts.jua(fontSize: 16, color: AppColors.textMain),
        bodyMedium: GoogleFonts.jua(fontSize: 14, color: AppColors.textSub),
      ),
    );
  }
}
