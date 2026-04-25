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

## 디자인 콘셉트

앱 아이콘은 이미지 생성 모델로 만든 민트색 파일 전송 아이콘을 사용합니다. 상단에는 우측에서 좌측으로 흐르는 큰 화살표, 하단에는 좌측에서 우측으로 흐르는 큰 화살표, 중앙에는 파일 문서가 있어 파일 전달 앱이라는 의미가 바로 보이도록 했습니다.

자세한 디자인 가이드는 [docs/brand-design.md](docs/brand-design.md)를 참고하세요.

브랜드 자산:

- `assets/brand/openfiletransfer-mark.svg`
- `assets/brand/openfiletransfer-icon-generated.png`
- `assets/brand/openfiletransfer-icon-1024.png`
- `assets/brand/openfiletransfer-icon-512.png`
