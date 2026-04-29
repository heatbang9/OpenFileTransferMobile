# 모바일 앱 빌드와 배포

이 문서는 OpenFileTransfer Mobile의 Android/iOS 빌드, 계정 준비, OS 제약, 배포 절차를 정리합니다.

## 현재 상태

- GitHub Actions에서 `flutter analyze`, `flutter test`, `flutter build apk --debug`를 검증합니다.
- Android debug APK 빌드는 자동 검증됩니다.
- Android release AAB/APK와 iOS IPA는 서명 키와 배포 계정이 필요하므로 아직 자동 배포하지 않습니다.
- 앱 아이콘과 Android/iOS 로컬 네트워크/foreground service 권한 설정 스크립트는 CI에서 적용됩니다.

## Android 빌드

로컬 Flutter SDK가 설치된 환경에서 실행합니다.

```bash
flutter pub get
dart run flutter_launcher_icons
flutter build apk --debug
flutter build apk --release
flutter build appbundle --release
```

Google Play 배포는 일반적으로 `appbundle` 산출물인 `.aab`를 사용합니다.

```text
build/app/outputs/bundle/release/app-release.aab
```

## Android 계정과 서명 준비

필요한 것:

- Google Play Console 개발자 계정
- 앱 패키지 이름 확정
- Play App Signing 설정
- 업로드 키 또는 CI용 signing keystore
- 개인정보 처리방침 URL
- 로컬 네트워크/파일 접근/알림 권한 설명 문구

권장 진행:

1. Google Play Console 계정을 만들고 개발자 프로필 검증을 완료합니다.
2. 앱 패키지 이름을 확정합니다. 예: `dev.openfiletransfer.mobile`
3. Play App Signing을 사용하고 업로드 키를 분리합니다.
4. GitHub Actions에는 keystore 파일을 base64 secret으로 저장하고, 비밀번호/alias도 secret으로 분리합니다.
5. 릴리즈 워크플로우에서 `flutter build appbundle --release`를 실행합니다.
6. 내부 테스트 트랙에 먼저 배포하고 실제 Android 기기에서 SSDP/gRPC/foreground service를 검증합니다.

## Android OS 제약

- Android는 장시간 전송/수신 진행률 표시를 위해 foreground service를 사용합니다.
- Android 14 이상은 foreground service type 선언이 필요하므로 `dataSync`를 사용합니다.
- Android 15 이상에서 `dataSync` foreground service는 24시간 동안 총 6시간 제한이 있습니다.
- 사용자가 알림을 끄거나 배터리 최적화가 강하게 적용된 기기에서는 장시간 수신 대기가 제한될 수 있습니다.

현재 앱은 모바일 수신 모드가 켜져 있는 동안 foreground service 알림을 유지합니다. 다만 미승인 전송 요청을 앱이 전면에 없을 때 알림 action으로 승인/거부하는 UX는 아직 남은 작업입니다.

## iOS 빌드

iOS 빌드는 macOS + Xcode + Apple Developer Program 계정이 필요합니다.

```bash
flutter pub get
dart run flutter_launcher_icons
flutter build ios --release
flutter build ipa --release
```

산출물:

```text
build/ios/archive/*.xcarchive
build/ios/ipa/*.ipa
```

## iOS 계정과 서명 준비

필요한 것:

- Apple Developer Program 계정
- App Store Connect 앱 레코드
- Bundle ID
- Distribution certificate
- Provisioning profile
- 앱 개인정보/권한 설명 문구
- 로컬 네트워크 사용 목적 설명

권장 진행:

1. Apple Developer 계정에서 Bundle ID를 등록합니다.
2. App Store Connect에 앱 레코드를 만듭니다.
3. Xcode에서 Signing & Capabilities를 설정합니다.
4. TestFlight용 `flutter build ipa --release`를 생성합니다.
5. App Store Connect 또는 Transporter로 업로드합니다.
6. TestFlight에서 로컬 네트워크 권한, 파일 선택, 앱 전면/백그라운드 전환을 검증합니다.

## iOS OS 제약

- iOS는 Android foreground service처럼 앱이 임의 gRPC 서버를 장시간 유지하는 모델이 아닙니다.
- 앱이 전면 또는 짧은 백그라운드 시간 안에 있을 때 모바일-to-모바일 수신을 우선 지원합니다.
- 대용량/장시간 전송은 background `URLSession` 기반 HTTP/HTTPS fallback을 별도로 구현하는 방향이 현실적입니다.

## 릴리즈 전 체크리스트

- Android 실제 기기에서 SSDP 탐색이 동작하는지 확인
- Android 실제 기기에서 앱을 백그라운드로 내린 뒤 foreground service 수신 대기가 유지되는지 확인
- Android 15 기기에서 장시간 `dataSync` 제한 시나리오 확인
- iOS 실제 기기에서 로컬 네트워크 권한 팝업과 SSDP/descriptor 접근 확인
- 모바일-to-모바일 승인 팝업, 항상 허용, 거부, 1:N 전송 확인
- 개인정보 처리방침과 권한 설명 문구 준비

## 공식 참고

- Flutter Android 배포: <https://docs.flutter.dev/deployment/android>
- Flutter iOS 배포: <https://docs.flutter.dev/deployment/ios>
- Google Play Console 시작: <https://support.google.com/googleplay/android-developer/answer/9859062>
- Android 15 foreground service 제한: <https://developer.android.com/about/versions/15/behavior-changes-15>
- Apple background download: <https://developer.apple.com/documentation/foundation/downloading-files-in-the-background>
