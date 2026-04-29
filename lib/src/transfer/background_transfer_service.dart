import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

enum TransferDirection {
  sending,
  receiving;

  String get label => switch (this) {
        TransferDirection.sending => '전송',
        TransferDirection.receiving => '수신',
      };
}

class BackgroundTransferSnapshot {
  const BackgroundTransferSnapshot({
    required this.active,
    required this.direction,
    required this.fileName,
    required this.progress,
    required this.message,
  });

  const BackgroundTransferSnapshot.idle()
      : active = false,
        direction = TransferDirection.sending,
        fileName = '',
        progress = 0,
        message = '백그라운드 전송 대기 중';

  final bool active;
  final TransferDirection direction;
  final String fileName;
  final double progress;
  final String message;

  int get percent => (progress.clamp(0, 1) * 100).round();
}

class BackgroundTransferService extends ChangeNotifier {
  BackgroundTransferSnapshot _snapshot = const BackgroundTransferSnapshot.idle();
  bool _configured = false;
  bool _receiveServerActive = false;
  String _receiveServerEndpoint = '';
  int _receiveServerSecondsLeft = 0;

  BackgroundTransferSnapshot get snapshot => _snapshot;

  static void initCommunicationPort() {
    FlutterForegroundTask.initCommunicationPort();
  }

  Future<void> configure() async {
    if (_configured) {
      return;
    }
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'open_file_transfer_background_transfer',
        channelName: 'OpenFileTransfer 전송',
        channelDescription: '파일 전송과 수신 진행 상태를 표시합니다.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _configured = true;
  }

  Future<void> requestNotificationPermission() async {
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  Future<void> startTransfer({
    required TransferDirection direction,
    required String fileName,
  }) async {
    await configure();
    await requestNotificationPermission();

    final text = _notificationText(direction, fileName, 0);
    await _startOrUpdateForegroundService(
      title: 'OpenFileTransfer ${direction.label} 중',
      text: text,
    );
    _setSnapshot(
      BackgroundTransferSnapshot(
        active: true,
        direction: direction,
        fileName: fileName,
        progress: 0,
        message: text,
      ),
    );
  }

  Future<void> startReceiveServer({
    required String endpoint,
    required int secondsLeft,
  }) async {
    await configure();
    await requestNotificationPermission();
    _receiveServerActive = true;
    _receiveServerEndpoint = endpoint;
    _receiveServerSecondsLeft = secondsLeft;
    final text = _receiveServerText();
    await _startOrUpdateForegroundService(
      title: 'OpenFileTransfer 모바일 수신 대기',
      text: text,
    );
    _setSnapshot(
      BackgroundTransferSnapshot(
        active: true,
        direction: TransferDirection.receiving,
        fileName: '모바일 수신 모드',
        progress: 0,
        message: text,
      ),
    );
  }

  Future<void> updateReceiveServer({
    required String endpoint,
    required int secondsLeft,
  }) async {
    if (!_receiveServerActive) {
      return;
    }
    _receiveServerEndpoint = endpoint;
    _receiveServerSecondsLeft = secondsLeft;
    final text = _receiveServerText();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'OpenFileTransfer 모바일 수신 대기',
        notificationText: text,
        notificationInitialRoute: '/',
      );
    }
    final current = _snapshot;
    if (current.fileName == '모바일 수신 모드') {
      _setSnapshot(
        BackgroundTransferSnapshot(
          active: true,
          direction: TransferDirection.receiving,
          fileName: '모바일 수신 모드',
          progress: 0,
          message: text,
        ),
      );
    }
  }

  Future<void> updateProgress(double progress) async {
    final current = _snapshot;
    if (!current.active) {
      return;
    }
    final nextProgress = progress.clamp(0, 1).toDouble();
    final text = _notificationText(current.direction, current.fileName, nextProgress);
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'OpenFileTransfer ${current.direction.label} 중',
        notificationText: text,
        notificationInitialRoute: '/',
      );
    }
    _setSnapshot(
      BackgroundTransferSnapshot(
        active: true,
        direction: current.direction,
        fileName: current.fileName,
        progress: nextProgress,
        message: text,
      ),
    );
  }

  Future<void> completeTransfer() async {
    final current = _snapshot;
    if (!current.active) {
      return;
    }
    final text = '${current.fileName} ${current.direction.label} 완료';
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'OpenFileTransfer 완료',
        notificationText: text,
        notificationInitialRoute: '/',
      );
      unawaited(Future<void>.delayed(const Duration(seconds: 2), () async {
        if (_receiveServerActive) {
          await _restoreReceiveServerNotification();
        } else {
          await FlutterForegroundTask.stopService();
        }
      }));
    }
    if (_receiveServerActive) {
      _setSnapshot(
        BackgroundTransferSnapshot(
          active: true,
          direction: current.direction,
          fileName: current.fileName,
          progress: 1,
          message: text,
        ),
      );
    } else {
      _setSnapshot(
        BackgroundTransferSnapshot(
          active: false,
          direction: current.direction,
          fileName: current.fileName,
          progress: 1,
          message: text,
        ),
      );
    }
  }

  Future<void> stop({bool force = false}) async {
    if (_receiveServerActive && !force) {
      await _restoreReceiveServerNotification();
      return;
    }
    _receiveServerActive = false;
    _receiveServerEndpoint = '';
    _receiveServerSecondsLeft = 0;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    _setSnapshot(const BackgroundTransferSnapshot.idle());
  }

  Future<void> stopReceiveServer() async {
    await stop(force: true);
  }

  void _setSnapshot(BackgroundTransferSnapshot snapshot) {
    _snapshot = snapshot;
    notifyListeners();
  }

  String _notificationText(TransferDirection direction, String fileName, double progress) {
    final percent = (progress.clamp(0, 1) * 100).round();
    return '$fileName ${direction.label} 중 · $percent%';
  }

  Future<void> _startOrUpdateForegroundService({
    required String title,
    required String text,
  }) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
        notificationInitialRoute: '/',
      );
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 8742,
        serviceTypes: Platform.isAndroid ? [ForegroundServiceTypes.dataSync] : null,
        notificationTitle: title,
        notificationText: text,
        notificationInitialRoute: '/',
        callback: openFileTransferBackgroundTaskStart,
      );
    }
  }

  Future<void> _restoreReceiveServerNotification() async {
    if (!_receiveServerActive) {
      return;
    }
    final text = _receiveServerText();
    await _startOrUpdateForegroundService(
      title: 'OpenFileTransfer 모바일 수신 대기',
      text: text,
    );
    _setSnapshot(
      BackgroundTransferSnapshot(
        active: true,
        direction: TransferDirection.receiving,
        fileName: '모바일 수신 모드',
        progress: 0,
        message: text,
      ),
    );
  }

  String _receiveServerText() {
    final secondsLeft = _receiveServerSecondsLeft.clamp(0, 24 * 60 * 60);
    final minutes = (secondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (secondsLeft % 60).toString().padLeft(2, '0');
    return '수신 대기 중 · $_receiveServerEndpoint · $minutes:$seconds';
  }
}

@pragma('vm:entry-point')
void openFileTransferBackgroundTaskStart() {
  FlutterForegroundTask.setTaskHandler(OpenFileTransferTaskHandler());
}

class OpenFileTransferTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    FlutterForegroundTask.sendDataToMain(<String, Object>{
      'type': 'started',
      'timestamp': timestamp.toIso8601String(),
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.sendDataToMain(<String, Object>{
      'type': 'heartbeat',
      'timestamp': timestamp.toIso8601String(),
    });
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) {
      return;
    }
    final title = data['title']?.toString();
    final text = data['text']?.toString();
    if (title == null || text == null) {
      return;
    }
    FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
      notificationInitialRoute: '/',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    FlutterForegroundTask.sendDataToMain(<String, Object>{
      'type': 'destroyed',
      'isTimeout': isTimeout,
      'timestamp': timestamp.toIso8601String(),
    });
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationDismissed() {}

  @override
  void onNotificationPressed() {}
}
