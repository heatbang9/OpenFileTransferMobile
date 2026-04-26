import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceProfile {
  const DeviceProfile({
    required this.deviceId,
    required this.deviceName,
  });

  final String deviceId;
  final String deviceName;

  DeviceProfile copyWith({
    String? deviceId,
    String? deviceName,
  }) {
    return DeviceProfile(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
    );
  }
}

class DeviceProfileStore {
  static const _deviceIdKey = 'open_file_transfer.device_id';
  static const _deviceNameKey = 'open_file_transfer.device_name';

  Future<DeviceProfile> load() async {
    final preferences = await SharedPreferences.getInstance();
    var deviceId = preferences.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await preferences.setString(_deviceIdKey, deviceId);
    }

    var deviceName = preferences.getString(_deviceNameKey);
    if (deviceName == null || deviceName.trim().isEmpty) {
      deviceName = 'Mobile ${deviceId.substring(0, 8)}';
      await preferences.setString(_deviceNameKey, deviceName);
    }

    return DeviceProfile(
      deviceId: deviceId,
      deviceName: deviceName,
    );
  }

  Future<DeviceProfile> saveName(String deviceName) async {
    final current = await load();
    final next = current.copyWith(deviceName: deviceName.trim());
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_deviceNameKey, next.deviceName);
    return next;
  }
}
