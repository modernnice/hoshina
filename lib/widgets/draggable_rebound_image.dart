import 'package:flutter/material.dart';

class DraggableReboundImage extends StatefulWidget {
  const DraggableReboundImage({
    super.key,
    required this.assetPath,
    required this.left,
    required this.top,
    required this.size,
    this.maxDragDistance = 48,
  });

  final String assetPath;
  final double left;
  final double top;
  final double size;
  final double maxDragDistance;

  @override
  State<DraggableReboundImage> createState() => _DraggableReboundImageState();
}

class _DraggableReboundImageState extends State<DraggableReboundImage> {
  double _dragOffsetX = 0;
  bool _dragging = false;

  void _updateOffset(double delta) {
    final next = (_dragOffsetX + delta).clamp(
      -widget.maxDragDistance,
      widget.maxDragDistance,
    );
    setState(() {
      _dragOffsetX = next;
    });
  }

  void _resetOffset() {
    setState(() {
      _dragging = false;
      _dragOffsetX = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.left,
      top: widget.top,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {
          if (_dragging) {
            return;
          }
          setState(() {
            _dragging = true;
          });
        },
        onHorizontalDragUpdate: (details) {
          _updateOffset(details.delta.dx);
        },
        onHorizontalDragEnd: (_) => _resetOffset(),
        onHorizontalDragCancel: _resetOffset,
        child: AnimatedContainer(
          duration: _dragging
              ? Duration.zero
              : const Duration(milliseconds: 360),
          curve: Curves.easeOutBack,
          transform: Matrix4.translationValues(_dragOffsetX, 0, 0),
          child: Image.asset(
            widget.assetPath,
            width: widget.size,
            height: widget.size,
          ),
        ),
      ),
    );
  }
}
