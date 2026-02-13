import 'package:flutter/material.dart';

extension ColorExt on Color {
  Color withBrightness(double factor) {
    final hsl = HSLColor.fromColor(this);
    return hsl
        .withLightness((hsl.lightness * factor).clamp(0.0, 1.0))
        .toColor();
  }

  Color blend(Color other, double amount) {
    return Color.lerp(this, other, amount) ?? this;
  }
}
