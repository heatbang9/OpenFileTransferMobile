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
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/brand/openfiletransfer-icon-512.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

IconData iconForTransferDirection(bool upload) {
  return upload ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded;
}
