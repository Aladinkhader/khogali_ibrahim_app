import 'package:flutter/material.dart';

/// الألوان الأساسية لتطبيق الشيخ أبو الحسن خوجلي إبراهيم
/// الهوية البصرية: أزرق داكن + سماوي
class AppColors {
  AppColors._();

  /// الخلفية الأساسية
  static const Color background = Color(0xFF0D2047);

  /// خلفية داكنة جدًا (تُستخدم في Splash و Bottom Nav)
  static const Color veryDarkBackground = Color(0xFF081630);

  /// خلفية البطاقات الداكنة
  static const Color cardDark = Color(0xFF102B55);

  /// لون بداية تدرج البطاقات
  static const Color cardGradientStart = Color(0xFF164B73);

  /// لون نهاية تدرج البطاقات
  static const Color cardGradientEnd = Color(0xFF0D2047);

  /// اللون الأساسي الأزرق السماوي
  /// (أزرار، أيقونات نشطة، حدود)
  static const Color primaryTeal = Color(0xFF18C7DE);

  /// نص ثانوي
  static const Color secondaryText = Color(0xFFA9C4D6);

  /// نص فاتح
  static const Color lightText = Color(0xFFD8EAF0);

  /// النص الرئيسي
  static const Color mainText = Color(0xFFF4F8F9);

  /// تدرج البطاقات الرئيسية (Hero Card)
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      cardGradientStart,
      cardGradientEnd,
    ],
  );

  /// تدرج بطاقات الأقسام
  static const LinearGradient categoryCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF123A63),
      Color(0xFF0D2047),
    ],
  );
}
