# OpenFileTransfer Mobile

![OpenFileTransfer Mobile icon](assets/brand/openfiletransfer-icon-512.png)

OpenFileTransfer 모바일 앱 저장소입니다. Android/iOS 네이티브 앱을 우선 목표로 하며, Flutter로 구현합니다.

## 왜 Flutter 네이티브인가

파일 전송 앱은 로컬 네트워크 탐색, 파일 선택, 백그라운드 전송, OS 권한 처리가 중요합니다. 브라우저/PWA는 UDP 기반 SSDP 탐색과 표준 gRPC 호출에 제약이 있어 1차 앱으로는 적합하지 않습니다.

## 실행

```bash
git submodule update --init --recursive
flutter pub get
./scripts/generate-dart-proto.sh
flutter test
flutter run
```

## CI 검증

GitHub Actions에서 다음을 확인합니다.

- `flutter pub get`
- `dart run flutter_launcher_icons`
- `flutter analyze`
- `flutter test`
- Android debug APK build

현재 로컬 환경에는 Flutter SDK가 없어서 CI 기반 검증을 사용합니다.

## 백그라운드 전송

Android는 전송/수신 중 앱을 나가도 작업을 계속 유지하기 위해 foreground service를 사용합니다. 구현 기준은 `flutter_foreground_task`이며, Android 14 이상 요구사항에 맞춰 `dataSync` foreground service type을 선언합니다.

- `lib/src/transfer/background_transfer_service.dart`가 전송 시작, 수신 시작, 진행률 갱신, 완료/중지를 담당합니다.
- UI의 `백그라운드 전송` 패널은 같은 민트 디자인으로 진행률 원형/선형 표시를 제공합니다.
- Android 알림 영역에는 `OpenFileTransfer 전송 중`, `OpenFileTransfer 수신 중`, 진행 퍼센트가 표시됩니다.
- foreground service가 실행 중일 때 Android 뒤로가기는 앱 종료가 아니라 최소화로 동작하도록 `WithForegroundTask`를 적용했습니다.
- `scripts/configure-android-foreground-service.sh`는 `flutter create` 후 AndroidManifest에 `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`, foreground service 선언을 추가합니다.
- 실제 gRPC `SendFile` 송신과 `ReceiveFile` 수신 루프에서 `startTransfer`, `updateProgress`, `completeTransfer`를 호출합니다.

iOS는 Android처럼 임의 장시간 네트워크 작업을 계속 돌리는 모델이 아닙니다. `flutter_foreground_task`도 iOS에서는 강제 종료 시 즉시 중단되고, 백그라운드 실행 시간이 제한됩니다. iOS에서 긴 파일 전송을 안정화하려면 다음 단계에서 `URLSession` background transfer를 쓰는 HTTP/HTTPS 전송 경로를 별도 검토하는 편이 현실적입니다.

참고 문서:

- [flutter_foreground_task](https://pub.dev/packages/flutter_foreground_task)
- [Android foreground service type: dataSync](https://developer.android.com/about/versions/14/changes/fgs-types-required#data-sync)
- [Apple BackgroundTasks](https://developer.apple.com/documentation/BackgroundTasks)

## 현재 통신 상태

- 모바일 앱은 SSDP `M-SEARCH`로 같은 네트워크의 OpenFileTransfer PC 서버를 찾고, 선택한 서버 주소로 바로 gRPC `Handshake` 후 `SendFile` client-streaming 파일 전송을 수행합니다.
- 모바일 앱은 `ListFiles`로 PC 서버 수신함을 조회하고, 선택한 파일을 `ReceiveFile` server-streaming으로 내려받습니다.
- 모바일 전송은 PC 서버와 같은 X25519 + HKDF-SHA256 세션 키와 AES-256-GCM chunk 암호화를 사용합니다.
- 송신/수신 진행률은 Android foreground service 알림과 앱 UI의 `백그라운드 전송` 패널에 반영됩니다.
- 모바일 내부 저장소에는 자체 생성 UUID와 사용자가 지정한 디바이스 이름을 저장하고, `Handshake` 때 PC 서버에 함께 전달합니다.
- AndroidManifest에는 인터넷/네트워크/멀티캐스트 권한을 추가하고, iOS Info.plist에는 로컬 네트워크 사용 설명을 추가합니다.
- 모바일 앱은 PC 서버와 `Handshake` 후 `SubscribeEvents` 스트림을 유지해서 서버 메시지, 파일 수신, 연결 상태 이벤트를 UI에서 받을 수 있습니다.
- 서버가 아무 연결도 없는 모바일 앱에 임의로 먼저 접속해 push하는 방식은 아닙니다.
- UUID는 디바이스 식별과 표시/신뢰 목록용입니다. 파일 암호화 키는 UUID만 보고 재사용하지 않고, 매 연결마다 X25519/HKDF로 새 AES-256-GCM 세션 키를 파생합니다.

## 승인/화이트리스트 방향

PC 서버는 미승인 모바일 디바이스의 업로드/다운로드 요청을 확인 팝업으로 막고, 승인된 UUID는 바로 통과시키는 흐름을 먼저 구현했습니다. 모바일 앱 자체가 서버 롤을 가질 때도 같은 정책을 적용합니다.

- 모바일 저장소에는 `SharedPreferences` 기반 `trusted_devices` 목록을 두고, 상대 UUID/이름/항상 허용 여부/최근 발견 시각/수신 횟수를 저장합니다.
- 모바일 서버 롤이 켜져 있을 때 미승인 UUID의 `SendFile` 요청은 앱 내 확인 팝업으로 `이번만 허용`, `항상 허용`, `거부` 중 하나를 선택해야 진행됩니다.
- `항상 허용`된 UUID는 다음 전송부터 확인 없이 바로 수신합니다. 다만 파일 payload 암호화 키는 UUID로 재사용하지 않고 매 Handshake마다 새로 파생합니다.
- Android foreground service 알림은 모바일-to-모바일 수신 진행률도 표시합니다. 알림 action 기반 백그라운드 승인 UX는 다음 단계입니다.

## 모바일-to-모바일과 1:N 전송 검토

모바일-to-모바일은 모바일 앱도 서버 롤을 가져야 하므로 먼저 단기 활성 수신 모드로 시작했습니다.

- `모바일 수신 모드`에서 `10분 열기`를 누르면 앱이 임시 gRPC 서버, SSDP responder, HTTP descriptor를 함께 시작합니다.
- 다른 모바일 앱은 같은 네트워크에서 `서버 찾기`를 누르면 임시 수신 모드인 모바일을 OpenFileTransfer 서버처럼 발견하고 기존 `파일 보내기`로 전송할 수 있습니다.
- 받는 모바일은 상대 모바일의 UUID와 표시 이름을 저장하고, 미승인 기기는 수신 승인 팝업을 띄웁니다.
- 모바일 임시 서버는 `ListFiles`와 `ReceiveFile`도 제공하므로, 상대 모바일이 수신함 파일을 조회하고 내려받는 흐름까지 같은 gRPC 계약으로 처리합니다.
- 수신 중에는 앱 UI의 `모바일 수신 모드` 패널과 Android 알림 영역에 진행률이 표시됩니다.
- `모바일 수신 모드` 패널에서 발견된 모바일 디바이스를 항상 허용하거나 해제할 수 있습니다.
- 받은 파일은 앱 문서 폴더의 `OpenFileTransfer/MobileInbox` 하위 폴더에 저장됩니다.
- 10분이 지나거나 사용자가 `중지`를 누르면 gRPC 서버와 SSDP responder를 닫습니다.
- Android: 단기 수신 모드를 켜면 foreground service 알림을 유지해 앱을 백그라운드로 내려도 수신 대기 상태가 더 잘 유지되도록 합니다. 전송이 시작되면 같은 알림에서 진행률을 표시하고, 완료 후 다시 수신 대기 알림으로 돌아갑니다.
- iOS: 장시간 백그라운드 서버 대기는 제약이 커서 앱이 전면 또는 제한된 백그라운드 시간 안에 있을 때 수신을 우선 지원합니다.
- 1:N 전송: 발견된 여러 서버를 체크하고 같은 파일을 각 서버로 순차 전송합니다. 대상별 성공/실패 결과도 전송 패널에 표시합니다.
- 같은 proto와 암호화 Handshake를 유지하되, 서버 기능을 모바일에 넣기 전 generated Dart gRPC 서비스 코드로 전환하는 것이 유지보수에 유리합니다.

추가 피쳐 정리와 구현 상태는 [docs/mobile-to-mobile-features.md](docs/mobile-to-mobile-features.md)와 [docs/feature-status.md](docs/feature-status.md)에 따로 정리했습니다.

## PC 서버로 파일 보내기

1. PC 앱에서 서버를 시작합니다.
2. 모바일 앱의 `내 디바이스`에서 표시 이름을 저장합니다.
3. `서버 찾기`를 눌러 OpenFileTransfer 서버를 찾고 원하는 PC 서버를 선택합니다.
4. Android 에뮬레이터에서 로컬 PC 서버로 보낼 때는 직접 입력값 `10.0.2.2:39091`도 사용할 수 있습니다.
5. `서버 이벤트`에서 `구독`을 누르면 PC 서버 이벤트가 모바일 UI에 표시됩니다.
6. `파일 선택` 후 `파일 보내기`를 누릅니다.

현재 구현은 proto generated Dart 파일 없이 gRPC client method와 필요한 protobuf wire encoding을 직접 정의합니다. 이후 `protoc` 생성물을 CI에 안정적으로 포함하면 수동 wire codec은 생성 코드로 교체할 수 있습니다.

## PC 서버에서 파일 받기

1. PC 앱에서 서버를 시작하고, PC 또는 모바일에서 파일을 한 번 보내 서버 수신함에 저장합니다.
2. 모바일 앱에서 서버를 선택하거나 주소를 입력합니다.
3. `서버 수신함`의 `새로고침`을 눌러 `ListFiles` 결과를 조회합니다.
4. 원하는 파일의 `받기`를 누르면 `ReceiveFile` 스트림으로 내려받고, 진행률이 앱 UI와 Android 알림 영역에 표시됩니다.
5. 받은 파일은 앱 문서 폴더의 `OpenFileTransfer` 하위 폴더에 저장됩니다.

## 디자인 콘셉트

앱 아이콘은 이미지 생성 모델로 만든 민트색 파일 전송 아이콘을 사용합니다. 상단에는 우측에서 좌측으로 흐르는 큰 화살표, 하단에는 좌측에서 우측으로 흐르는 큰 화살표, 중앙에는 파일 문서가 있어 파일 전달 앱이라는 의미가 바로 보이도록 했습니다.

자세한 디자인 가이드는 [docs/brand-design.md](docs/brand-design.md)를 참고하세요.

브랜드 자산:

- `assets/brand/openfiletransfer-mark.svg`
- `assets/brand/openfiletransfer-icon-generated.png`
- `assets/brand/openfiletransfer-icon-1024.png`
- `assets/brand/openfiletransfer-icon-512.png`
