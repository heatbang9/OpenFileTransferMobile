# OpenFileTransfer Mobile 디자인

![OpenFileTransfer Mobile icon](../assets/brand/openfiletransfer-icon-512.png)

## 콘셉트

모바일 앱은 PC 앱과 같은 민트/틸 브랜드를 사용하되, 작은 화면에서 상태, 탐색, 전송, 수신함을 세로 흐름으로 배치합니다. 앱 내부 로고는 Flutter `CustomPainter`로 그려서 SVG 런타임 의존성을 추가하지 않습니다.

## 색상

| Token | Hex | 용도 |
| --- | --- | --- |
| Mint 50 | `#E9FFF6` | 화면 배경, 선택 상태 |
| Mint 300 | `#BFEFD9` | 패널/버튼 테두리 |
| Mint 600 | `#2BBF8A` | 브랜드 포인트 |
| Teal 700 | `#147D67` | 주요 버튼 |
| Teal 900 | `#0A5C4D` | 아이콘 선, 강한 텍스트 |
| Ink | `#15372F` | 주요 텍스트 |

## UI 규칙

- PC 앱과 동일하게 패널과 버튼 radius는 8px을 기본으로 둡니다.
- 주요 액션인 서버 찾기는 `Teal 700` filled button을 사용합니다.
- 파일 선택, 파일 보내기, 수신함 조회는 민트 테두리의 outlined button을 사용합니다.
- 앱 아이콘과 인앱 로고는 상단 우측에서 좌측, 하단 좌측에서 우측으로 흐르는 같은 태극형 양방향 전송 마크를 사용합니다.
- Android/iOS launcher icon은 `flutter_launcher_icons`로 같은 PNG 원본에서 생성합니다.
