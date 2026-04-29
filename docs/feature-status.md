# OpenFileTransfer Mobile 피쳐 상태

## 구현 완료

- 모바일 클라이언트 롤: SSDP 탐색, `Handshake`, `SendFile`, `ListFiles`, `ReceiveFile`, `SubscribeEvents`를 사용합니다.
- 모바일 서버 롤: `10분 열기` 단기 수신 모드에서 gRPC 서버, SSDP responder, HTTP descriptor를 실행합니다.
- 모바일-to-모바일: 임시 모바일 서버를 발견해 파일을 보내고, 수신함 파일을 조회/다운로드할 수 있습니다.
- 승인/화이트리스트: 상대 UUID와 이름을 저장하고, 미승인 디바이스는 `이번만 허용`, `항상 허용`, `거부` 팝업을 거칩니다.
- 1:N 전송: 발견된 여러 PC/모바일 서버를 체크하고 같은 파일을 순차 전송합니다.
- 진행률: 송신, 수신, 모바일-to-모바일 송수신 진행률을 UI와 Android foreground service 알림에 표시합니다.
- Android 수신 대기: 모바일 수신 모드가 켜져 있는 동안 foreground service 알림을 유지합니다.
- 디자인: PC 앱과 같은 민트/틸 색상, 로고, 아이콘 콘셉트를 사용합니다.
- 암호화: 각 연결마다 X25519/HKDF-SHA256으로 새 AES-256-GCM 파일 payload 키를 파생합니다.

## 남은 구현 후보

- 앱이 전면에 없을 때 미승인 수신 요청을 foreground notification action으로 허용/거부합니다.
- 1:N 전송 큐에 재시도, 취소, 대상별 진행률 고정 표시를 추가합니다.
- 신뢰 목록에서 디바이스 삭제, 이름 변경, 마지막 전송 시간을 관리합니다.
- iOS 장시간 백그라운드 전송은 `URLSession` background transfer 기반 HTTP/HTTPS fallback으로 별도 안정화합니다.
