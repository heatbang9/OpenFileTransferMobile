class MobileImplementationPlan {
  const MobileImplementationPlan();

  List<String> get steps => const [
        'SSDP 탐색용 플랫폼 채널 또는 검증된 플러그인 선정',
        'Dart gRPC 생성 코드 연결 또는 수동 protobuf codec 제거',
        'Handshake와 세션 키 파생 구현 완료',
        'SendFile client-streaming 전송 구현 완료',
        'SubscribeEvents 스트림 유지 및 서버 이벤트 UI 반영',
        'Android foreground service로 앱 이탈 후 전송 진행률 알림 유지',
        'file_picker로 파일 선택 후 SendFile 스트리밍 전송 완료',
        '서버 수신함 조회와 다운로드 UI 구현',
      ];
}
