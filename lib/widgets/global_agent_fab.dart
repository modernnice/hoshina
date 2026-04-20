import 'dart:async';

import 'package:drama_tracker/screens/agent/agent_chat_page.dart';
import 'package:flutter/material.dart';

class GlobalAgentFab extends StatefulWidget {
  const GlobalAgentFab({
    super.key,
    required this.navigatorKey,
  });

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<GlobalAgentFab> createState() => _GlobalAgentFabState();
}

class _GlobalAgentFabState extends State<GlobalAgentFab> {
  static const double _fabSize = 110;
  static const double _fabVisibleHalf = _fabSize / 2;
  static const double _sideTolerance = 2;
  // 气泡位置调节参数：
  // - _bubbleTopOffset：负值越大，气泡越靠上
  // - _bubbleEdgeInset：值越小，气泡越靠屏幕边缘
  static const double _bubbleTopOffset = -16;
  static const double _bubbleEdgeInset = _fabVisibleHalf + 30;
  static const double _bubbleMaxWidth = 180;
  double? _left;
  double? _top;
  bool _hidden = false;
  bool _bubbleVisible = false;
  bool _bubbleDismissedAfterEnterAgent = false;
  Timer? _bubbleCycleTimer;
  Timer? _bubbleHideTimer;

  @override
  void initState() {
    super.initState();
    _startBubbleCycle();
  }

  @override
  void dispose() {
    _bubbleCycleTimer?.cancel();
    _bubbleHideTimer?.cancel();
    super.dispose();
  }

  void _startBubbleCycle() {
    _bubbleCycleTimer?.cancel();
    _bubbleCycleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _hidden || _bubbleDismissedAfterEnterAgent) {
        return;
      }
      setState(() {
        _bubbleVisible = true;
      });
      _bubbleHideTimer?.cancel();
      _bubbleHideTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) {
          return;
        }
        setState(() {
          _bubbleVisible = false;
        });
      });
    });
  }

  double _clampTop({
    required double value,
    required double minTop,
    required double maxTop,
  }) {
    return value.clamp(minTop, maxTop);
  }

  double _clampLeft({
    required double value,
    required double leftDock,
    required double rightDock,
  }) {
    return value.clamp(leftDock, rightDock);
  }

  double _nearestDockLeft({
    required double currentLeft,
    required double leftDock,
    required double rightDock,
  }) {
    final distanceToLeft = (currentLeft - leftDock).abs();
    final distanceToRight = (rightDock - currentLeft).abs();
    return distanceToLeft <= distanceToRight ? leftDock : rightDock;
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final leftDock = media.padding.left - _fabVisibleHalf;
        final rightDock = constraints.maxWidth - media.padding.right - _fabVisibleHalf;
        final minTop = 8.0 + media.padding.top;
        final maxTop = constraints.maxHeight - _fabSize - 8.0 - media.padding.bottom;

        _left ??= rightDock;
        _top ??= _clampTop(value: maxTop - 70, minTop: minTop, maxTop: maxTop);
        _left = _clampLeft(value: _left!, leftDock: leftDock, rightDock: rightDock);
        _top = _clampTop(value: _top!, minTop: minTop, maxTop: maxTop);
        final isDockedLeft = (_left! - leftDock).abs() <= _sideTolerance;
        final isDockedRight = (_left! - rightDock).abs() <= _sideTolerance;
        final isMiddle = !isDockedLeft && !isDockedRight;
        final canDisplayBubble = !_bubbleDismissedAfterEnterAgent && (isDockedLeft || isDockedRight);
        final showBubble = _bubbleVisible && canDisplayBubble;
        final bubbleColor = Colors.white.withValues(alpha: 0.82);

        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              left: _left!,
              top: _top!,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (canDisplayBubble)
                    Positioned(
                      top: _bubbleTopOffset,
                      left: isDockedLeft ? _bubbleEdgeInset : null,
                      right: isDockedRight ? _bubbleEdgeInset : null,
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: showBubble ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 420),
                          curve: Curves.easeIn,
                          child: AnimatedSlide(
                            offset: showBubble ? const Offset(0, 0) : const Offset(0, 0.05),
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOut,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  constraints: const BoxConstraints(maxWidth: _bubbleMaxWidth),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: bubbleColor,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: const Color(0xFFD9E6FF)),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x220F172A),
                                        blurRadius: 10,
                                        offset: Offset(0, 4),
                                      )
                                    ],
                                  ),
                                  child: const Text(
                                    '点我可以与星奈聊天哦',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF475569),
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: -6,
                                  left: isDockedLeft ? 14 : null,
                                  right: isDockedRight ? 14 : null,
                                  child: CustomPaint(
                                    size: const Size(12, 8),
                                    painter: _BubbleTailPainter(
                                      fillColor: bubbleColor,
                                      strokeColor: const Color(0xFFD9E6FF),
                                      leanRight: isDockedRight,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _left = _clampLeft(
                          value: _left! + details.delta.dx,
                          leftDock: leftDock,
                          rightDock: rightDock,
                        );
                        _top = _clampTop(
                          value: _top! + details.delta.dy,
                          minTop: minTop,
                          maxTop: maxTop,
                        );
                      });
                    },
                    onPanEnd: (_) {
                      setState(() {
                        _left = _nearestDockLeft(
                          currentLeft: _left!,
                          leftDock: leftDock,
                          rightDock: rightDock,
                        );
                      });
                    },
                    onPanCancel: () {
                      setState(() {
                        _left = _nearestDockLeft(
                          currentLeft: _left!,
                          leftDock: leftDock,
                          rightDock: rightDock,
                        );
                      });
                    },
                    onTap: () async {
                      final navigator = widget.navigatorKey.currentState;
                      if (navigator == null) {
                        return;
                      }
                      setState(() {
                        _hidden = true;
                        _bubbleVisible = false;
                        _bubbleDismissedAfterEnterAgent = true;
                      });
                      await navigator.push(
                        MaterialPageRoute(builder: (_) => const AgentChatPage()),
                      );
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _hidden = false;
                      });
                    },
                    child: Transform.scale(
                      scale: isMiddle ? 1.5 : 1.0,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: _fabSize,
                        height: _fabSize,
                        child: ClipOval(
                          child: Stack(
                            children: [
                              if (isMiddle)
                                Center(
                                  child: Image.asset(
                                    'assets/icons/middle.png',
                                    width: _fabSize * 1.25,
                                    height: _fabSize * 1.25,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) {
                                      return const Icon(
                                        Icons.smart_toy_rounded,
                                        color: Color(0xFF00BFFF),
                                        size: 24,
                                      );
                                    },
                                  ),
                                )
                              else
                                SizedBox.expand(
                                  child: Row(
                                    children: [
                                      if (isDockedRight) ...[
                                        SizedBox(
                                          width: _fabSize / 2,
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: Image.asset(
                                              'assets/icons/floating.png',
                                              width: _fabSize * 1.10,
                                              height: _fabSize * 1.10,
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) {
                                                return const Icon(
                                                  Icons.smart_toy_rounded,
                                                  color: Color(0xFF00BFFF),
                                                  size: 24,
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                        const Expanded(child: SizedBox.shrink()),
                                      ] else ...[
                                        const Expanded(child: SizedBox.shrink()),
                                        SizedBox(
                                          width: _fabSize / 2,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Transform(
                                              alignment: Alignment.center,
                                              transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
                                              child: Image.asset(
                                                'assets/icons/floating.png',
                                                width: _fabSize * 0.90,
                                                height: _fabSize * 0.90,
                                                fit: BoxFit.contain,
                                                errorBuilder: (_, __, ___) {
                                                  return const Icon(
                                                    Icons.smart_toy_rounded,
                                                    color: Color(0xFF00BFFF),
                                                    size: 24,
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  _BubbleTailPainter({
    required this.fillColor,
    required this.strokeColor,
    required this.leanRight,
  });

  final Color fillColor;
  final Color strokeColor;
  final bool leanRight;

  @override
  void paint(Canvas canvas, Size size) {
    final horizontalShift = size.width * 0.22;
    final apexX = (size.width / 2) + (leanRight ? horizontalShift : -horizontalShift);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(apexX, size.height)
      ..lineTo(size.width, 0)
      ..close();

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final strokePath = Path()
      ..moveTo(0, 0)
      ..lineTo(apexX, size.height)
      ..lineTo(size.width, 0);
    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(strokePath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.leanRight != leanRight;
  }
}
