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
      ..style = PaintingStyle.stroke
      ..strokeWidth = 150
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [OpenFileTransferColors.mint600, OpenFileTransferColors.mint500],
      ).createShader(const Rect.fromLTWH(156, 220, 664, 260));
    final lowerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 150
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [OpenFileTransferColors.teal700, Color(0xff32bfa0)],
      ).createShader(const Rect.fromLTWH(204, 542, 664, 260));

    canvas.drawPath(
      Path()
        ..moveTo(806, 356)
        ..cubicTo(676, 192, 396, 183, 225, 382),
      upperPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(218, 668)
        ..cubicTo(348, 832, 628, 841, 799, 642),
      lowerPaint,
    );

    canvas.drawPath(
      _leftArrowHead(),
      Paint()..color = OpenFileTransferColors.mint600,
    );
    canvas.drawPath(
      _rightArrowHead(),
      Paint()..color = OpenFileTransferColors.teal700,
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

  Path _leftArrowHead() {
    final path = Path()
      ..moveTo(60, 438)
      ..cubicTo(26, 404, 50, 346, 98, 346)
      ..lineTo(238, 346)
      ..cubicTo(286, 346, 310, 404, 276, 438)
      ..lineTo(206, 508)
      ..cubicTo(185, 529, 151, 529, 130, 508)
      ..lineTo(60, 438)
      ..close();
    return path;
  }

  Path _rightArrowHead() {
    final path = Path()
      ..moveTo(964, 586)
      ..cubicTo(998, 620, 974, 678, 926, 678)
      ..lineTo(786, 678)
      ..cubicTo(738, 678, 714, 620, 748, 586)
      ..lineTo(818, 516)
      ..cubicTo(839, 495, 873, 495, 894, 516)
      ..lineTo(964, 586)
      ..close();
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

IconData iconForTransferDirection(bool upload) {
  return upload ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded;
}
