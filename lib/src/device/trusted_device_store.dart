import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TrustedDevice {
  const TrustedDevice({
    required this.deviceId,
    required this.deviceName,
    required this.trusted,
    required this.lastSeenUnixTimeMs,
    required this.transferCount,
  });

  final String deviceId;
  final String deviceName;
  final bool trusted;
  final int lastSeenUnixTimeMs;
  final int transferCount;

  TrustedDevice copyWith({
    String? deviceId,
    String? deviceName,
    bool? trusted,
    int? lastSeenUnixTimeMs,
    int? transferCount,
  }) {
    return TrustedDevice(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      trusted: trusted ?? this.trusted,
      lastSeenUnixTimeMs: lastSeenUnixTimeMs ?? this.lastSeenUnixTimeMs,
      transferCount: transferCount ?? this.transferCount,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'deviceId': deviceId,
      'deviceName': deviceName,
      'trusted': trusted,
      'lastSeenUnixTimeMs': lastSeenUnixTimeMs,
      'transferCount': transferCount,
    };
  }

  factory TrustedDevice.fromJson(Map<String, Object?> json) {
    return TrustedDevice(
      deviceId: json['deviceId']?.toString() ?? '',
      deviceName: json['deviceName']?.toString() ?? '알 수 없는 디바이스',
      trusted: json['trusted'] == true,
      lastSeenUnixTimeMs: (json['lastSeenUnixTimeMs'] as num?)?.toInt() ?? 0,
      transferCount: (json['transferCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class TrustedDeviceStore {
  static const _devicesKey = 'open_file_transfer.trusted_devices';

  Future<List<TrustedDevice>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_devicesKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <TrustedDevice>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <TrustedDevice>[];
    }
    return decoded
        .whereType<Map>()
        .map((item) => TrustedDevice.fromJson(Map<String, Object?>.from(item)))
        .where((device) => device.deviceId.isNotEmpty)
        .toList(growable: false);
  }

  Future<TrustedDevice> remember({
    required String deviceId,
    required String deviceName,
    bool? trusted,
    bool transferCompleted = false,
  }) async {
    final devices = await load();
    final now = DateTime.now().millisecondsSinceEpoch;
    final index = devices.indexWhere((device) => device.deviceId == deviceId);
    final current = index == -1 ? null : devices[index];
    final next = TrustedDevice(
      deviceId: deviceId,
      deviceName: deviceName.trim().isEmpty
          ? (current?.deviceName ?? '알 수 없는 디바이스')
          : deviceName.trim(),
      trusted: trusted ?? current?.trusted ?? false,
      lastSeenUnixTimeMs: now,
      transferCount: (current?.transferCount ?? 0) + (transferCompleted ? 1 : 0),
    );
    final updated = <TrustedDevice>[
      for (final device in devices)
        if (device.deviceId != deviceId) device,
      next,
    ]..sort((a, b) => b.lastSeenUnixTimeMs.compareTo(a.lastSeenUnixTimeMs));
    await _save(updated);
    return next;
  }

  Future<List<TrustedDevice>> setTrusted(String deviceId, bool trusted) async {
    final devices = await load();
    final updated = devices
        .map(
          (device) => device.deviceId == deviceId ? device.copyWith(trusted: trusted) : device,
        )
        .toList(growable: false);
    await _save(updated);
    return updated;
  }

  Future<bool> isTrusted(String deviceId) async {
    final devices = await load();
    return devices.any((device) => device.deviceId == deviceId && device.trusted);
  }

  Future<void> _save(List<TrustedDevice> devices) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      devices.map((device) => device.toJson()).toList(growable: false),
    );
    await preferences.setString(_devicesKey, encoded);
  }
}
