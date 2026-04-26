import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_file_transfer_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('초기 화면이 표시된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const OpenFileTransferApp());
    await tester.pump();

    expect(find.text('OpenFileTransfer'), findsOneWidget);
    expect(find.text('내 디바이스'), findsOneWidget);
    expect(find.text('서버 찾기'), findsOneWidget);
    expect(find.byIcon(Icons.radar_rounded), findsOneWidget);
    expect(find.text('PC 서버 주소'), findsOneWidget);
    expect(find.text('파일 보내기'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('백그라운드 전송'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('백그라운드 전송'), findsOneWidget);
  });
}
