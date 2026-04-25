import 'dart:math' as math;

import 'package:flutter/material.dart';

class OpenFileTransferColors {
  const OpenFileTransferColors._();

  static const mint50 = Color(0xffe9fff6);
  static const mint100 = Color(0xffd8f8e8);
  static const mint300 = Color(0xffbfefd9);
  static const mint500 = Color(0xff5ed6a3);
  static const mint600 = Color(0xff2bbf8a);
  static const teal700 = Color(0xff147d67);
  static const teal900 = Color(0xff0a5c4d);
  static const ink = Color(0xff15372f);
  static const surface = Color(0xfff7fffb);
}

class OpenFileTransferMark extends StatelessWidget {
  const OpenFileTransferMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: const _OpenFileTransferMarkPainter(),
      ),
    );
  }
}

class _OpenFileTransferMarkPainter extends CustomPainter {
  const _OpenFileTransferMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 1024;
    canvas.save();
    canvas.scale(scale);

    final background = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 1024, 1024),
      const Radius.circular(248),
    );
    final backgroundPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [OpenFileTransferColors.mint50, OpenFileTransferColors.mint300],
      ).createShader(const Rect.fromLTWH(0, 0, 1024, 1024));
    canvas.drawRRect(background, backgroundPaint);

    canvas.drawCircle(
      const Offset(512, 512),
      348,
      Paint()..color = Colors.white.withValues(alpha: 0.72),
    );

    final upperPaint = Paint()
      ..shader = const LinearGradient(
        colors: [OpenFileTransferColors.mint600, OpenFileTransferColors.mint500],
      ).createShader(const Rect.fromLTWH(240, 160, 560, 360));
    final lowerPaint = Paint()
      ..shader = const LinearGradient(
        colors: [OpenFileTransferColors.teal700, Color(0xff32bfa0)],
      ).createShader(const Rect.fromLTWH(240, 500, 560, 360));

    canvas.drawPath(_upperFlowPath(), upperPaint);
    canvas.drawPath(_lowerFlowPath(), lowerPaint);

    final arrowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 58
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = OpenFileTransferColors.teal900;

    canvas.drawLine(const Offset(512, 276), const Offset(512, 486), arrowPaint);
    canvas.drawPath(
      Path()
        ..moveTo(430, 368)
        ..lineTo(512, 276)
        ..lineTo(594, 368),
      arrowPaint,
    );
    canvas.drawLine(const Offset(512, 748), const Offset(512, 538), arrowPaint);
    canvas.drawPath(
      Path()
        ..moveTo(594, 656)
        ..lineTo(512, 748)
        ..lineTo(430, 656),
      arrowPaint,
    );

    canvas.drawCircle(
      const Offset(512, 512),
      72,
      Paint()..color = const Color(0xffeffff7),
    );
    canvas.drawCircle(
      const Offset(512, 512),
      72,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 34
        ..color = OpenFileTransferColors.teal900,
    );

    canvas.restore();
  }

  Path _upperFlowPath() {
    final path = Path()
      ..moveTo(516, 170)
      ..cubicTo(627, 170, 729, 229, 785, 324)
      ..cubicTo(800, 349, 787, 381, 759, 389)
      ..lineTo(603, 435)
      ..cubicTo(568, 445, 537, 408, 552, 375)
      ..lineTo(574, 328)
      ..cubicTo(555, 320, 535, 316, 514, 316)
      ..cubicTo(431, 316, 359, 377, 344, 458)
      ..cubicTo(339, 487, 315, 509, 285, 509)
      ..lineTo(184, 509)
      ..cubicTo(154, 509, 130, 483, 135, 453)
      ..cubicTo(167, 291, 322, 170, 516, 170)
      ..close();
    return path;
  }

  Path _lowerFlowPath() {
    final path = Path()
      ..moveTo(508, 854)
      ..cubicTo(397, 854, 295, 795, 239, 700)
      ..cubicTo(224, 675, 237, 643, 265, 635)
      ..lineTo(421, 589)
      ..cubicTo(456, 579, 487, 616, 472, 649)
      ..lineTo(450, 696)
      ..cubicTo(469, 704, 489, 708, 510, 708)
      ..cubicTo(593, 708, 665, 647, 680, 566)
      ..cubicTo(685, 537, 709, 515, 739, 515)
      ..lineTo(840, 515)
      ..cubicTo(870, 515, 894, 541, 889, 571)
      ..cubicTo(857, 733, 702, 854, 508, 854)
      ..close();
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

IconData iconForTransferDirection(bool upload) {
  return upload ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
}

Matrix4 slightLogoTilt() {
  return Matrix4.rotationZ(-math.pi / 90);
}
