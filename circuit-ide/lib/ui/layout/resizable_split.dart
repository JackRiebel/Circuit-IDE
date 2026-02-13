import 'package:flutter/material.dart';

class ResizableHandle extends StatefulWidget {
  final Axis direction;
  final void Function(double delta) onDrag;
  final Color color;

  const ResizableHandle({
    super.key,
    required this.direction,
    required this.onDrag,
    required this.color,
  });

  @override
  State<ResizableHandle> createState() => _ResizableHandleState();
}

class _ResizableHandleState extends State<ResizableHandle> {
  bool _isHovering = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = widget.direction == Axis.horizontal;
    final isActive = _isHovering || _isDragging;

    return MouseRegion(
      cursor: isHorizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanEnd: (_) => setState(() => _isDragging = false),
        onPanUpdate: (details) {
          widget.onDrag(isHorizontal ? details.delta.dx : details.delta.dy);
        },
        child: Container(
          width: isHorizontal ? 4 : null,
          height: isHorizontal ? null : 4,
          color: isActive
              ? Theme.of(context).colorScheme.primary
              : widget.color,
        ),
      ),
    );
  }
}
