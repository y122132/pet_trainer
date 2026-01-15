import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';

class AppTextStyles {
  // Just helpers that proxy to what we might want
  static TextStyle get title => GoogleFonts.jua(
    fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textMain
  );
  
  static TextStyle get body => GoogleFonts.jua(
    fontSize: 16, color: AppColors.textMain
  );
  
  static TextStyle get subBody => GoogleFonts.jua(
    fontSize: 14, color: AppColors.textSub
  );

  // Legacy mappings
  static TextStyle get button => title.copyWith(fontSize: 18);
  static TextStyle get base => body;
}

class AppDecorations {
  // Warm, soft shadows
  static final List<BoxShadow> softShadow = [
    BoxShadow(
      color: AppColors.primary.withOpacity(0.08), // Warm shadow
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: Colors.black.withOpacity(0.03), // Subtle depth
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  static final List<BoxShadow> floatShadow = [
    BoxShadow(
      color: AppColors.primary.withOpacity(0.15),
      blurRadius: 20,
      offset: const Offset(0, 10),
    )
  ];
  
  // Glowing effect for character focus
  static final List<BoxShadow> glowShadow = [
    BoxShadow(
      color: AppColors.accent.withOpacity(0.4),
      blurRadius: 30,
      spreadRadius: 5,
    ),
    BoxShadow(
      color: Colors.white.withOpacity(0.8),
      blurRadius: 20,
      spreadRadius: -5,
    ),
  ];

  static BorderRadius cardRadius = BorderRadius.circular(24);
  
  // Legacy mappings
  static List<BoxShadow> get cardShadow => softShadow;
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double opacity;
  final double blur;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;

  const GlassContainer({
    super.key,
    required this.child,
    this.opacity = 0.6, // Slightly more opaque for readability on cream
    this.blur = 15.0,   // Softer blur
    this.borderRadius,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.border,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding ?? const EdgeInsets.all(20),
            decoration: BoxDecoration(
              // Warm white tint
              color: AppColors.surface.withOpacity(opacity),
              borderRadius: borderRadius ?? BorderRadius.circular(24),
              border: border ?? Border.all(
                color: Colors.white.withOpacity(0.6),
                width: 1.5,
              ),
              boxShadow: boxShadow ?? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                )
              ]
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class ThemedBackground extends StatelessWidget {
  final Widget child;
  const ThemedBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background, // Explicit warm background
      child: Stack(
        children: [
          // Subtle warm gradient blob
          Positioned(
            top: -100,
            right: -100,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.secondary.withOpacity(0.1),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withOpacity(0.1),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
