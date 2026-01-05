import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// --- Color Palette ---
class AppColors {
  static const Color background = Color(0xFFFFF9E6);
  static const Color primaryBrown = Color(0xFF5D4037);
  static const Color secondaryBrown = Color(0xFF8D6E63);

  // Stat Colors
  static const Color statStr = Color(0xFFFF8A80);
  static const Color statInt = Color(0xFF82B1FF);
  static const Color statDex = Color(0xFFB9F6CA);
  static const Color statDef = Color(0xFFD7CCC8);
}

// --- Text Styles ---
class AppTextStyles {
  static final TextStyle base = GoogleFonts.jua(
    color: AppColors.primaryBrown,
    letterSpacing: 1.2,
  );

  static final TextStyle title = base.copyWith(
    fontSize: 28,
    fontWeight: FontWeight.bold,
  );

  static final TextStyle button = base.copyWith(
    fontSize: 18,
    color: Colors.white,
    fontWeight: FontWeight.bold,
  );
  
  static final TextStyle body = base.copyWith(
    fontSize: 16,
    color: AppColors.secondaryBrown,
  );
}

// --- Decorations ---
class AppDecorations {
  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Colors.black12,
      blurRadius: 10,
      offset: const Offset(0, 4),
    )
  ];

  static final BorderRadius cardRadius = BorderRadius.circular(30);
}

// --- Background Widget ---
class ThemedBackground extends StatelessWidget {
  final Widget child;
  const ThemedBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: AppColors.background),
        Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            image: DecorationImage(
              image: const AssetImage('assets/images/login_bg.png'),
              fit: BoxFit.cover, // Cover might look better than tile
              opacity: 0.3,
            ),
          ),
        ),
        child,
      ],
    );
  }
}
