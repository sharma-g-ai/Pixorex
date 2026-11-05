import 'package:flutter/material.dart';

class FrameOverlay extends StatelessWidget {
  const FrameOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _FramePainter(),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 200),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Align nameplate within frame',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final cornerPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    // Frame rect — centered, 80% width, 40% height
    final left = size.width * 0.1;
    final top = size.height * 0.25;
    final right = size.width * 0.9;
    final bottom = size.height * 0.65;
    final rect = Rect.fromLTRB(left, top, right, bottom);

    // Dim area outside frame
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.4);
    // Top
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, top), dimPaint);
    // Bottom
    canvas.drawRect(Rect.fromLTRB(0, bottom, size.width, size.height), dimPaint);
    // Left
    canvas.drawRect(Rect.fromLTRB(0, top, left, bottom), dimPaint);
    // Right
    canvas.drawRect(Rect.fromLTRB(right, top, size.width, bottom), dimPaint);

    // Dashed border
    canvas.drawRect(rect, paint);

    // Corner highlights
    const cornerLen = 30.0;
    // Top-left
    canvas.drawLine(Offset(left, top), Offset(left + cornerLen, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left, top + cornerLen), cornerPaint);
    // Top-right
    canvas.drawLine(Offset(right, top), Offset(right - cornerLen, top), cornerPaint);
    canvas.drawLine(Offset(right, top), Offset(right, top + cornerLen), cornerPaint);
    // Bottom-left
    canvas.drawLine(Offset(left, bottom), Offset(left + cornerLen, bottom), cornerPaint);
    canvas.drawLine(Offset(left, bottom), Offset(left, bottom - cornerLen), cornerPaint);
    // Bottom-right
    canvas.drawLine(Offset(right, bottom), Offset(right - cornerLen, bottom), cornerPaint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - cornerLen), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
