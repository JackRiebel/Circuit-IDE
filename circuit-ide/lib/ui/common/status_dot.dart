import 'package:flutter/material.dart';

enum DotStatus { connected, connecting, disconnected, error }

class StatusDot extends StatelessWidget {
  final DotStatus status;
  final double size;
  final String? label;

  const StatusDot({
    super.key,
    required this.status,
    this.size = 8,
    this.label,
  });

  Color _color() {
    return switch (status) {
      DotStatus.connected => const Color(0xFF4CAF50),
      DotStatus.connecting => const Color(0xFFFF9800),
      DotStatus.disconnected => const Color(0xFF9E9E9E),
      DotStatus.error => const Color(0xFFF44336),
    };
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _color(),
        boxShadow: status == DotStatus.connected
            ? [
                BoxShadow(
                  color: _color().withValues(alpha: 0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );

    if (label != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot,
          const SizedBox(width: 6),
          Text(
            label!,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.7),
            ),
          ),
        ],
      );
    }

    return dot;
  }
}
