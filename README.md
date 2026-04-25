# OpenFileTransfer Mobile

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
- `flutter analyze`
- `flutter test`
- Android debug APK build

현재 로컬 환경에는 Flutter SDK가 없어서 CI 기반 검증을 사용합니다.

