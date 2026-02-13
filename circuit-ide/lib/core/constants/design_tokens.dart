import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Cisco Momentum-inspired spacing scale (4px base unit)
class Spacing {
  static const double xs = 2;
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double xxxxl = 48;
}

class Radii {
  static const double xs = 3;
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double xl = 12;
  static const double pill = 1000;
}

/// Enterprise type scale — compact but readable
class FontSizes {
  static const double xxs = 9;
  static const double xs = 10;
  static const double sm = 11;
  static const double md = 12;
  static const double base = 13;
  static const double lg = 14;
  static const double xl = 16;
  static const double xxl = 20;
  static const double title = 24;
  static const double display = 32;
}

class EditorDefaults {
  static const double fontSize = 14;
  static const double lineHeight = 1.5;
  static const String fontFamily = 'JetBrains Mono';
  static const String fallbackFontFamily = 'Menlo';
}

class AnimationDurations {
  static const Duration instant = Duration(milliseconds: 50);
  static const Duration fast = Duration(milliseconds: 100);
  static const Duration normal = Duration(milliseconds: 150);
  static const Duration smooth = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);
  static const Duration panel = Duration(milliseconds: 250);
}

class AnimationCurves {
  static const Curve snappy = Cubic(0.2, 0.8, 0.2, 1.0);
  static const Curve smooth = Cubic(0.4, 0.0, 0.2, 1.0);
}

class LayoutDimensions {
  static const double activityBarWidth = 48;
  static const double sidePanelMinWidth = 200;
  static const double sidePanelDefaultWidth = 260;
  static const double sidePanelMaxWidth = 500;
  static const double statusBarHeight = 28;
  static const double tabBarHeight = 36;
  static const double breadcrumbHeight = 24;
  static const double chatInputMinHeight = 80;
  static const double chatPanelMinWidth = 300;
  static const double chatPanelDefaultWidth = 380;
  static const double terminalMinHeight = 100;
  static const double terminalDefaultHeight = 200;
  static const double terminalMaxHeight = 400;
  static const double chatPanelMaxWidth = 500;
  static const double titleBarHeight = 38;
}

class Shadows {
  static const List<BoxShadow> subtle = [
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> medium = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 8,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 16,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  static List<BoxShadow> glow(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.25),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.08),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> softGlow(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.15),
          blurRadius: 8,
        ),
      ];
}
