#!/usr/bin/env bash
set -euo pipefail

manifest_path="android/app/src/main/AndroidManifest.xml"

if [[ ! -f "${manifest_path}" ]]; then
  echo "AndroidManifest.xml을 찾지 못해 foreground service 설정을 건너뜁니다."
  exit 0
fi

python3 - <<'PY'
from pathlib import Path

path = Path("android/app/src/main/AndroidManifest.xml")
text = path.read_text()

permissions = [
    '<uses-permission android:name="android.permission.INTERNET" />',
    '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />',
    '<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />',
    '<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />',
    '<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />',
    '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />',
    '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
    '<uses-permission android:name="android.permission.WAKE_LOCK" />',
]

for permission in permissions:
    if permission not in text:
        manifest_start = text.find("<manifest")
        first_close = text.find(">\n", manifest_start)
        if first_close == -1:
            raise SystemExit("manifest 태그를 찾지 못했습니다.")
        text = text[: first_close + 2] + f"    {permission}\n" + text[first_close + 2 :]

service_name = "com.pravera.flutter_foreground_task.service.ForegroundService"
service = (
    '        <service\n'
    f'            android:name="{service_name}"\n'
    '            android:foregroundServiceType="dataSync"\n'
    '            android:exported="false" />'
)

if service_name not in text:
    text = text.replace("    </application>", f"{service}\n    </application>")

if 'android:usesCleartextTraffic=' not in text:
    text = text.replace("<application", '<application android:usesCleartextTraffic="true"', 1)

path.write_text(text)
PY
