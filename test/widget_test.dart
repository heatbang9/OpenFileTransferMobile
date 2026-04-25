import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_file_transfer_mobile/main.dart';

void main() {
  testWidgets('초기 화면이 표시된다', (tester) async {
    await tester.pumpWidget(const OpenFileTransferApp());

    expect(find.text('OpenFileTransfer'), findsOneWidget);
    expect(find.text('서버 찾기'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });
}

