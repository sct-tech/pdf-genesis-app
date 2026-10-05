import 'package:flutter/material.dart';

/// "Luminous Intelligence" palette from the Stitch design system.
class AppColors {
  const AppColors._();

  static const primary = Color(0xFF2563EB);
  static const primaryDark = Color(0xFF1D4ED8);
  static const indigo = Color(0xFF4F46E5);
  static const primaryTint = Color(0xFFEFF4FF);

  static const background = Color(0xFFFAF8FF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF8FAFC);
  static const border = Color(0xFFE2E8F0);

  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const textSubtle = Color(0xFF94A3B8);

  static const success = Color(0xFF047857);
  static const successTint = Color(0xFFECFDF5);
  static const danger = Color(0xFFBA1A1A);
  static const dangerTint = Color(0xFFFFF1F2);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, indigo],
  );
}
