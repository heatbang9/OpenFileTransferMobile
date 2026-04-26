#!/usr/bin/env bash
set -euo pipefail

plist_path="ios/Runner/Info.plist"

if [[ ! -f "${plist_path}" ]]; then
  echo "Info.plist를 찾지 못해 iOS local network 설정을 건너뜁니다."
  exit 0
fi

python3 - <<'PY'
from pathlib import Path

path = Path("ios/Runner/Info.plist")
text = path.read_text()

insert = """\t<key>NSLocalNetworkUsageDescription</key>
\t<string>OpenFileTransfer 서버를 찾고 파일을 전송하기 위해 로컬 네트워크 접근이 필요합니다.</string>
\t<key>NSBonjourServices</key>
\t<array>
\t\t<string>_openfiletransfer._tcp</string>
\t</array>
"""

if "NSLocalNetworkUsageDescription" not in text:
    text = text.replace("</dict>", f"{insert}</dict>")

path.write_text(text)
PY
