import 'package:flutter/material.dart';

class RetroColors {
  const RetroColors({
    required this.primary,
    required this.dark,
    required this.darker,
  });

  final Color primary;

  final Color dark;

  final Color darker;

  static const RetroColors green = RetroColors(
    primary: Color(0xFF4CAF50),
    dark: Color(0xFF12351A),
    darker: Color(0xFF071B0C),
  );

  static const RetroColors amber = RetroColors(
    primary: Color(0xFFFFB300),
    dark: Color(0xFF3D2B00),
    darker: Color(0xFF1C1400),
  );

  static const RetroColors cyan = RetroColors(
    primary: Color(0xFF00E5FF),
    dark: Color(0xFF00343D),
    darker: Color(0xFF00171D),
  );

  static const RetroColors magenta = RetroColors(
    primary: Color(0xFFFF3D7F),
    dark: Color(0xFF3D0A1F),
    darker: Color(0xFF1C050F),
  );

  static const List<RetroColors> all = [green, amber, cyan, magenta];
}