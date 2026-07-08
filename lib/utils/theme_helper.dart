import 'package:flutter/material.dart';

extension ThemeColors on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  Color get scaffoldBg => isDarkMode ? const Color(0xFF0F0F12) : const Color(0xFFF3F3F7);
  Color get cardBg => isDarkMode ? const Color(0xFF16161A) : const Color(0xFFFFFFFF);
  Color get inputBg => isDarkMode ? const Color(0xFF1E1E22) : const Color(0xFFF9F9FB);
  Color get borderColor => isDarkMode ? const Color(0xFF232329) : const Color(0xFFE0E0E6);
  Color get inputBorderColor => isDarkMode ? const Color(0xFF2C2C35) : const Color(0xFFDCDCE2);
  
  Color get textColorPrimary => isDarkMode ? Colors.white : const Color(0xFF1F1F24);
  Color get textColorSecondary => isDarkMode ? Colors.grey : const Color(0xFF70707C);
  
  Color get listBg => isDarkMode ? const Color(0xFF1A1A1E) : const Color(0xFFF0F0F4);
}
