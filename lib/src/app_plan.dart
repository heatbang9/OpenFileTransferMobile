class MobileImplementationPlan {
  const MobileImplementationPlan();

  List<String> get steps => const [
        'SSDP 탐색으로 OpenFileTransfer 서버 목록 표시 완료',
        '내부 저장소에 모바일 UUID와 디바이스 이름 유지 완료',
        'Dart gRPC 생성 코드 연결 또는 수동 protobuf codec 제거',
        'Handshake와 세션 키 파생 구현 완료',
        'SendFile client-streaming 전송 구현 완료',
        'SubscribeEvents 스트림 유지 및 서버 이벤트 UI 반영',
        'Android foreground service로 앱 이탈 후 전송 진행률 알림 유지',
        'file_picker로 파일 선택 후 SendFile 스트리밍 전송 완료',
        '서버 수신함 조회와 다운로드 UI 구현',
        '모바일 서버 롤, 모바일-to-모바일 SSDP 광고, 수신 승인 팝업 설계 필요',
        '모바일 1:N 다중 전송 UI와 전송 큐 구현 필요',
        '모바일 화이트리스트 승인/해제 저장소와 전송 승인 UX 구현 필요',
      ];
}
