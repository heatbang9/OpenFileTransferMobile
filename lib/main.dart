import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';

import 'src/brand/open_file_transfer_brand.dart';
import 'src/device/device_profile_store.dart';
import 'src/device/trusted_device_store.dart';
import 'src/discovery/ssdp_discovery_client.dart';
import 'src/network/mobile_transfer_client.dart';
import 'src/network/mobile_transfer_server.dart';
import 'src/transfer/background_transfer_service.dart';

final BackgroundTransferService _backgroundTransferService = BackgroundTransferService();
final DeviceProfileStore _deviceProfileStore = DeviceProfileStore();
final TrustedDeviceStore _trustedDeviceStore = TrustedDeviceStore();

bool _isMobilePeerServer(DiscoveredServer server) {
  return server.capabilities.contains('mobile-temporary-server');
}

class _SendTarget {
  const _SendTarget({
    required this.address,
    required this.deviceName,
    required this.mobilePeer,
  });

  final String address;
  final String deviceName;
  final bool mobilePeer;
}

class _SendTargetResult {
  const _SendTargetResult({
    required this.target,
    required this.success,
    required this.message,
  });

  final _SendTarget target;
  final bool success;
  final String message;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  BackgroundTransferService.initCommunicationPort();
  runApp(const OpenFileTransferApp());
}

class OpenFileTransferApp extends StatelessWidget {
  const OpenFileTransferApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenFileTransfer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: OpenFileTransferColors.mint600,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: OpenFileTransferColors.surface,
        appBarTheme: const AppBarTheme(
          backgroundColor: OpenFileTransferColors.surface,
          foregroundColor: OpenFileTransferColors.ink,
          centerTitle: false,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: OpenFileTransferColors.teal700,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: OpenFileTransferColors.teal900,
            side: const BorderSide(color: OpenFileTransferColors.mint300),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        useMaterial3: true,
      ),
      home: const WithForegroundTask(child: DeviceDiscoveryPage()),
    );
  }
}

class DeviceDiscoveryPage extends StatefulWidget {
  const DeviceDiscoveryPage({super.key});

  @override
  State<DeviceDiscoveryPage> createState() => _DeviceDiscoveryPageState();
}

class _DeviceDiscoveryPageState extends State<DeviceDiscoveryPage> {
  final TextEditingController _addressController = TextEditingController(text: '10.0.2.2:39091');
  final TextEditingController _deviceNameController = TextEditingController();
  String _status = '서버를 찾을 준비가 되었습니다.';
  DeviceProfile? _deviceProfile;
  List<DiscoveredServer> _servers = const <DiscoveredServer>[];
  DiscoveredServer? _selectedServer;
  Set<String> _selectedSendTargetIds = const <String>{};
  MobileTransferClient? _eventClient;
  MobileEventSubscription? _eventSubscription;
  final List<ServerEvent> _events = <ServerEvent>[];
  String? _selectedFilePath;
  String? _selectedFileName;
  TransferReceipt? _lastReceipt;
  List<_SendTargetResult> _sendResults = const <_SendTargetResult>[];
  List<FileEntry> _serverFiles = const <FileEntry>[];
  ReceivedFileResult? _lastReceivedFile;
  ActiveMobileTransferServer? _mobileServer;
  MobileReceivedFile? _lastPeerReceivedFile;
  List<TrustedDevice> _trustedDevices = const <TrustedDevice>[];
  MobileTransferProgress? _peerReceiveProgress;
  String? _peerReceiveNotificationTransferId;
  Timer? _mobileServerTicker;
  DateTime? _mobileServerExpiresAt;
  int _mobileServerSecondsLeft = 0;
  bool _discovering = false;
  bool _subscribing = false;
  bool _sending = false;
  bool _loadingInbox = false;
  bool _receiving = false;

  void _markPending(String text) {
    setState(() {
      _status = text;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadDeviceProfile();
    unawaited(_loadTrustedDevices());
  }

  Future<void> _loadDeviceProfile() async {
    final profile = await _deviceProfileStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _deviceProfile = profile;
      _deviceNameController.text = profile.deviceName;
    });
  }

  Future<void> _saveDeviceName() async {
    final nextName = _deviceNameController.text.trim();
    if (nextName.isEmpty) {
      _markPending('디바이스 이름을 입력하세요.');
      return;
    }
    final profile = await _deviceProfileStore.saveName(nextName);
    if (!mounted) {
      return;
    }
    setState(() {
      _deviceProfile = profile;
      _status = '${profile.deviceName} 이름으로 저장되었습니다.';
    });
  }

  Future<void> _loadTrustedDevices() async {
    final devices = await _trustedDeviceStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _trustedDevices = devices;
    });
  }

  Future<void> _rememberPeer(
    String deviceId,
    String deviceName, {
    bool? trusted,
    bool transferCompleted = false,
  }) async {
    if (deviceId.trim().isEmpty) {
      return;
    }
    await _trustedDeviceStore.remember(
      deviceId: deviceId,
      deviceName: deviceName,
      trusted: trusted,
      transferCompleted: transferCompleted,
    );
    await _loadTrustedDevices();
  }

  Future<void> _setPeerTrusted(String deviceId, bool trusted) async {
    final devices = await _trustedDeviceStore.setTrusted(deviceId, trusted);
    if (!mounted) {
      return;
    }
    setState(() {
      _trustedDevices = devices;
      _status = trusted
          ? '디바이스를 항상 허용했습니다.'
          : '디바이스 자동 허용을 해제했습니다.';
    });
  }

  Future<bool> _isTrustedPeer(String deviceId) async {
    if (_trustedDevices.any(
      (device) => device.deviceId == deviceId && device.trusted,
    )) {
      return true;
    }
    return _trustedDeviceStore.isTrusted(deviceId);
  }

  Future<void> _discoverServers() async {
    setState(() {
      _discovering = true;
      _status = 'OpenFileTransfer 서버 탐색 중';
    });
    try {
      final servers = await SsdpDiscoveryClient().discover();
      if (!mounted) {
        return;
      }
      setState(() {
        _servers = servers;
        _selectedSendTargetIds = _selectedSendTargetIds
            .where((id) => servers.any((server) => server.deviceId == id))
            .toSet();
        _status = servers.isEmpty ? '찾은 서버가 없습니다.' : '서버 ${servers.length}개를 찾았습니다.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'SSDP 탐색 실패: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _discovering = false;
        });
      }
    }
  }

  void _selectServer(DiscoveredServer server) {
    setState(() {
      _selectedServer = server;
      _addressController.text = server.address;
      _lastReceipt = null;
      _sendResults = const <_SendTargetResult>[];
      _serverFiles = const <FileEntry>[];
      _lastReceivedFile = null;
      _status = '${server.deviceName}에 연결할 준비가 되었습니다.';
    });
  }

  void _toggleSendTarget(DiscoveredServer server) {
    final next = Set<String>.from(_selectedSendTargetIds);
    if (next.contains(server.deviceId)) {
      next.remove(server.deviceId);
    } else {
      next.add(server.deviceId);
    }
    setState(() {
      _selectedSendTargetIds = next;
      _selectedServer = server;
      _addressController.text = server.address;
      _status = next.isEmpty ? '1:N 전송 대상이 비었습니다.' : '1:N 전송 대상 ${next.length}개 선택됨';
    });
  }

  Future<void> _subscribeSelectedServer() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      _markPending('구독할 PC 서버 주소를 입력하세요.');
      return;
    }
    setState(() {
      _subscribing = true;
      _status = '서버 이벤트 구독 중';
    });
    await _unsubscribeEvents(updateStatus: false);
    final profile = _deviceProfile ?? await _deviceProfileStore.load();
    final client = MobileTransferClient(
      address: address,
      clientDeviceId: profile.deviceId,
      clientName: profile.deviceName,
    );
    try {
      final subscription = await client.subscribeEvents(
        onEvent: (event) {
          if (!mounted) {
            return;
          }
          setState(() {
            _events.add(event);
            if (_events.length > 30) {
              _events.removeRange(0, _events.length - 30);
            }
            _status = '서버 이벤트 수신: ${event.message}';
          });
          if (event.type == 'file_received') {
            unawaited(_refreshInbox());
          }
        },
        onError: (error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _status = '서버 이벤트 구독 오류: $error';
          });
        },
      );
      if (!mounted) {
        await subscription.cancel();
        await client.close();
        return;
      }
      setState(() {
        _eventClient = client;
        _eventSubscription = subscription;
        _status = '서버 이벤트 구독 중';
      });
    } catch (error) {
      await client.close();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '서버 이벤트 구독 실패: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _subscribing = false;
        });
      }
    }
  }

  Future<void> _unsubscribeEvents({bool updateStatus = true}) async {
    await _eventSubscription?.cancel();
    await _eventClient?.close();
    _eventSubscription = null;
    _eventClient = null;
    if (mounted && updateStatus) {
      setState(() {
        _status = '서버 이벤트 구독을 해제했습니다.';
      });
    }
  }

  void _clearEvents() {
    setState(() {
      _events.clear();
    });
  }

  void _startBackgroundTransfer(TransferDirection direction) {
    final fileName = direction == TransferDirection.sending
        ? 'mobile-upload.bin'
        : 'pc-download.bin';
    _markPending('${direction.label} 백그라운드 서비스 시작 중');
    _backgroundTransferService.startTransfer(direction: direction, fileName: fileName).then((_) {
      if (!mounted) {
        return;
      }
      _markPending('${direction.label} 진행 상태가 알림 영역에 표시됩니다.');
    }).catchError((Object error) {
      if (!mounted) {
        return;
      }
      _markPending('백그라운드 서비스 시작 실패: $error');
    });
  }

  void _advanceBackgroundTransfer() {
    final nextProgress = _backgroundTransferService.snapshot.progress + 0.25;
    _backgroundTransferService.updateProgress(nextProgress).catchError((Object error) {
      if (!mounted) {
        return;
      }
      _markPending('진행률 갱신 실패: $error');
    });
  }

  void _completeBackgroundTransfer() {
    _backgroundTransferService.completeTransfer().catchError((Object error) {
      if (!mounted) {
        return;
      }
      _markPending('전송 완료 처리 실패: $error');
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    final file = result?.files.single;
    if (file?.path == null) {
      _markPending('파일 선택이 취소되었습니다.');
      return;
    }
    setState(() {
      _selectedFilePath = file!.path;
      _selectedFileName = file.name;
      _lastReceipt = null;
      _status = '${file.name} 선택됨';
    });
  }

  List<_SendTarget> _currentSendTargets(String manualAddress) {
    final discoveredTargets = _servers
        .where((server) => _selectedSendTargetIds.contains(server.deviceId))
        .map(
          (server) => _SendTarget(
            address: server.address,
            deviceName: server.deviceName,
            mobilePeer: _isMobilePeerServer(server),
          ),
        )
        .toList(growable: false);
    if (discoveredTargets.isNotEmpty) {
      return discoveredTargets;
    }
    if (manualAddress.isEmpty) {
      return const <_SendTarget>[];
    }
    final selected = _selectedServer;
    return <_SendTarget>[
      _SendTarget(
        address: manualAddress,
        deviceName: selected?.deviceName ?? '직접 입력 서버',
        mobilePeer: selected == null ? false : _isMobilePeerServer(selected),
      ),
    ];
  }

  Future<TransferReceipt> _sendFileToTarget({
    required _SendTarget target,
    required String filePath,
    required void Function(OpenFileTransferProgress progress) onProgress,
  }) async {
    MobileTransferClient? client;
    try {
      final profile = _deviceProfile ?? await _deviceProfileStore.load();
      client = MobileTransferClient(
        address: target.address,
        clientDeviceId: profile.deviceId,
        clientName: profile.deviceName,
      );
      final receipt = await client.sendFile(filePath, onProgress: onProgress);
      return receipt;
    } finally {
      await client?.close();
    }
  }

  Future<void> _sendSelectedFile() async {
    final filePath = _selectedFilePath;
    final fileName = _selectedFileName;
    final address = _addressController.text.trim();
    if (filePath == null || fileName == null) {
      _markPending('먼저 전송할 파일을 선택하세요.');
      return;
    }
    final targets = _currentSendTargets(address);
    if (targets.isEmpty) {
      _markPending('전송할 서버를 선택하거나 주소를 입력하세요.');
      return;
    }

    setState(() {
      _sending = true;
      _lastReceipt = null;
      _sendResults = const <_SendTargetResult>[];
      _status = targets.length == 1 ? '서버와 Handshake 중' : '1:N 전송 준비 중 · ${targets.length}개 대상';
    });
    final results = <_SendTargetResult>[];
    TransferReceipt? lastReceipt;
    try {
      await _backgroundTransferService.startTransfer(
        direction: TransferDirection.sending,
        fileName: fileName,
      );
      for (var index = 0; index < targets.length; index += 1) {
        final target = targets[index];
        try {
          final receipt = await _sendFileToTarget(
            target: target,
            filePath: filePath,
            onProgress: (progress) {
              final combinedProgress = (index + progress.progress) / targets.length;
              unawaited(_backgroundTransferService.updateProgress(combinedProgress));
              if (!mounted) {
                return;
              }
              setState(() {
                final percent = (progress.progress * 100).round();
                _status = '${target.deviceName} 전송 중 · $percent%';
              });
            },
          );
          lastReceipt = receipt;
          results.add(
            _SendTargetResult(
              target: target,
              success: true,
              message: '${receipt.fileName} · ${receipt.size} bytes',
            ),
          );
        } catch (error) {
          results.add(
            _SendTargetResult(
              target: target,
              success: false,
              message: error.toString(),
            ),
          );
        }
        if (mounted) {
          setState(() {
            _sendResults = List<_SendTargetResult>.unmodifiable(results);
          });
        }
      }

      final successCount = results.where((result) => result.success).length;
      if (successCount == 0) {
        await _backgroundTransferService.stop();
      } else {
        await _backgroundTransferService.completeTransfer();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _lastReceipt = lastReceipt;
        _status = successCount == 0
            ? '전송 실패 · 0/${targets.length}'
            : (successCount == targets.length
                ? '전송 완료 · $successCount/${targets.length}'
                : '전송 일부 완료 · $successCount/${targets.length}');
      });
    } catch (error) {
      await _backgroundTransferService.stop();
      if (!mounted) {
        return;
      }
      setStatusWithError(error);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _refreshInbox() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      _markPending('조회할 PC 서버 주소를 입력하세요.');
      return;
    }
    setState(() {
      _loadingInbox = true;
      _status = '서버 수신함 조회 중';
    });

    MobileTransferClient? client;
    try {
      final profile = _deviceProfile ?? await _deviceProfileStore.load();
      client = MobileTransferClient(
        address: address,
        clientDeviceId: profile.deviceId,
        clientName: profile.deviceName,
      );
      final files = await client.listFiles();
      if (!mounted) {
        return;
      }
      setState(() {
        _serverFiles = files;
        _status = files.isEmpty ? '서버 수신함이 비어 있습니다.' : '서버 파일 ${files.length}개 조회 완료';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setStatusWithError(error, action: '수신함 조회');
    } finally {
      await client?.close();
      if (mounted) {
        setState(() {
          _loadingInbox = false;
        });
      }
    }
  }

  Future<void> _receiveServerFile(FileEntry file) async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      _markPending('수신할 PC 서버 주소를 입력하세요.');
      return;
    }
    setState(() {
      _receiving = true;
      _lastReceivedFile = null;
      _status = '${file.fileName} 수신 준비 중';
    });

    MobileTransferClient? client;
    try {
      await _backgroundTransferService.startTransfer(
        direction: TransferDirection.receiving,
        fileName: file.fileName,
      );
      final documentsDir = await getApplicationDocumentsDirectory();
      final outputDir = Directory('${documentsDir.path}/OpenFileTransfer');
      final profile = _deviceProfile ?? await _deviceProfileStore.load();
      client = MobileTransferClient(
        address: address,
        clientDeviceId: profile.deviceId,
        clientName: profile.deviceName,
      );
      final result = await client.receiveFile(
        file,
        outputDir.path,
        onProgress: (progress) {
          unawaited(_backgroundTransferService.updateProgress(progress.progress));
          if (!mounted) {
            return;
          }
          setState(() {
            _status = '파일 수신 중 · ${(progress.progress * 100).round()}%';
          });
        },
      );
      await _backgroundTransferService.completeTransfer();
      if (!mounted) {
        return;
      }
      setState(() {
        _lastReceivedFile = result;
        _status = '${result.fileName} 수신 완료';
      });
    } catch (error) {
      await _backgroundTransferService.stop();
      if (!mounted) {
        return;
      }
      setStatusWithError(error, action: '수신');
    } finally {
      await client?.close();
      if (mounted) {
        setState(() {
          _receiving = false;
        });
      }
    }
  }

  Future<bool> _confirmPeerTransfer(MobileTransferRequest request) async {
    await _rememberPeer(request.peerDeviceId, request.peerName);
    if (!mounted) {
      return false;
    }
    final sizeLabel = request.totalBytes > 0
        ? '${request.totalBytes} bytes'
        : '크기 확인 중';
    final directionText = request.direction == MobileTransferDirection.incoming
        ? '보내려고 합니다'
        : '가져가려고 합니다';
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('모바일 파일 접근 승인'),
          content: Text(
            '${request.peerName}에서 ${request.fileName} 파일을 $directionText.\n'
            '디바이스 UUID: ${request.peerDeviceId}\n'
            '크기: $sizeLabel',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('deny'),
              child: const Text('거부'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop('once'),
              child: const Text('이번만 허용'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('always'),
              child: const Text('항상 허용'),
            ),
          ],
        );
      },
    );
    if (result == 'always') {
      await _rememberPeer(request.peerDeviceId, request.peerName, trusted: true);
      return true;
    }
    return result == 'once';
  }

  void _handlePeerReceiveProgress(MobileTransferProgress progress) {
    unawaited(() async {
      if (_peerReceiveNotificationTransferId != progress.transferId) {
        _peerReceiveNotificationTransferId = progress.transferId;
        await _backgroundTransferService.startTransfer(
          direction: progress.direction == MobileTransferDirection.incoming
              ? TransferDirection.receiving
              : TransferDirection.sending,
          fileName: progress.fileName,
        );
      }
      await _backgroundTransferService.updateProgress(progress.progress);
    }());
    if (!mounted) {
      return;
    }
    setState(() {
      _peerReceiveProgress = progress;
      final percent = (progress.progress * 100).round();
      _status = '${progress.peerName}와 모바일 ${progress.direction.label} 중 · $percent%';
    });
  }

  Future<void> _startTemporaryMobileServer() async {
    if (_mobileServer != null) {
      _markPending('모바일 수신 모드가 이미 실행 중입니다.');
      return;
    }
    final profile = _deviceProfile ?? await _deviceProfileStore.load();
    final documentsDir = await getApplicationDocumentsDirectory();
    final receiveDir = Directory('${documentsDir.path}/OpenFileTransfer/MobileInbox');
    final server = ActiveMobileTransferServer(
      deviceId: profile.deviceId,
      deviceName: profile.deviceName,
      receiveDirectory: receiveDir.path,
      ttl: const Duration(minutes: 10),
      onPeerSeen: (deviceId, deviceName) async {
        await _rememberPeer(deviceId, deviceName);
      },
      isTrustedDevice: _isTrustedPeer,
      onTransferApprovalRequest: _confirmPeerTransfer,
      onTransferProgress: _handlePeerReceiveProgress,
      onTransferCompleted: (deviceId, deviceName) async {
        await _rememberPeer(deviceId, deviceName, transferCompleted: true);
      },
      onFileReceived: (file) {
        unawaited(_backgroundTransferService.completeTransfer());
        _peerReceiveNotificationTransferId = null;
        if (!mounted) {
          return;
        }
        setState(() {
          _lastPeerReceivedFile = file;
          _peerReceiveProgress = null;
          _status = '${file.fileName} 모바일 수신 완료';
        });
      },
    );
    try {
      await server.start();
      if (!mounted) {
        await server.stop();
        return;
      }
      _mobileServerTicker?.cancel();
      final expiresAt = DateTime.now().add(const Duration(minutes: 10));
      final endpoint = '${server.hostAddress}:${server.grpcPort}';
      await _backgroundTransferService.startReceiveServer(
        endpoint: endpoint,
        secondsLeft: expiresAt.difference(DateTime.now()).inSeconds,
      );
      setState(() {
        _mobileServer = server;
        _mobileServerExpiresAt = expiresAt;
        _mobileServerSecondsLeft = expiresAt.difference(DateTime.now()).inSeconds;
        _status = '모바일 수신 모드 시작 · $endpoint';
      });
      _mobileServerTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        final currentServer = _mobileServer;
        final currentExpiresAt = _mobileServerExpiresAt;
        if (!mounted || currentServer == null || currentExpiresAt == null) {
          return;
        }
        final secondsLeft = currentExpiresAt.difference(DateTime.now()).inSeconds;
        if (secondsLeft <= 0) {
          unawaited(_stopTemporaryMobileServer(updateStatus: true));
          return;
        }
        final endpoint = '${currentServer.hostAddress}:${currentServer.grpcPort}';
        unawaited(
          _backgroundTransferService.updateReceiveServer(
            endpoint: endpoint,
            secondsLeft: secondsLeft,
          ),
        );
        setState(() {
          _mobileServerSecondsLeft = secondsLeft;
        });
      });
    } catch (error) {
      await server.stop();
      await _backgroundTransferService.stopReceiveServer();
      if (!mounted) {
        return;
      }
      setStatusWithError(error, action: '모바일 수신 모드 시작');
    }
  }

  Future<void> _stopTemporaryMobileServer({bool updateStatus = true}) async {
    final server = _mobileServer;
    _mobileServerTicker?.cancel();
    _mobileServerTicker = null;
    _mobileServer = null;
    _mobileServerExpiresAt = null;
    _mobileServerSecondsLeft = 0;
    _peerReceiveProgress = null;
    _peerReceiveNotificationTransferId = null;
    await server?.stop();
    await _backgroundTransferService.stopReceiveServer();
    if (mounted && updateStatus) {
      setState(() {
        _status = '모바일 수신 모드를 중지했습니다.';
      });
    }
  }

  void setStatusWithError(Object error, {String action = '전송'}) {
    setState(() {
      _status = '$action 실패: $error';
    });
  }

  @override
  void dispose() {
    unawaited(_unsubscribeEvents(updateStatus: false));
    unawaited(_stopTemporaryMobileServer(updateStatus: false));
    _addressController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OpenFileTransferMark(size: 32),
            SizedBox(width: 10),
            Text('OpenFileTransfer'),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusPanel(status: _status),
            const SizedBox(height: 16),
            _DeviceProfilePanel(
              profile: _deviceProfile,
              controller: _deviceNameController,
              onSave: _saveDeviceName,
            ),
            const SizedBox(height: 16),
            _DiscoveryPanel(
              discovering: _discovering,
              servers: _servers,
              selectedServer: _selectedServer,
              selectedSendTargetIds: _selectedSendTargetIds,
              onDiscover: _discoverServers,
              onSelectServer: _selectServer,
              onToggleSendTarget: _toggleSendTarget,
            ),
            const SizedBox(height: 16),
            _TransferPanel(
              addressController: _addressController,
              selectedFileName: _selectedFileName,
              lastReceipt: _lastReceipt,
              sendResults: _sendResults,
              selectedServer: _selectedServer,
              selectedSendTargetCount: _selectedSendTargetIds.length,
              sending: _sending,
              onDiscover: _discoverServers,
              onPickFile: _pickFile,
              onSend: _sendSelectedFile,
            ),
            const SizedBox(height: 16),
            _BackgroundTransferPanel(
              service: _backgroundTransferService,
              onStartSend: () => _startBackgroundTransfer(TransferDirection.sending),
              onStartReceive: () => _startBackgroundTransfer(TransferDirection.receiving),
              onAdvance: _advanceBackgroundTransfer,
              onComplete: _completeBackgroundTransfer,
              onStop: () {
                unawaited(_backgroundTransferService.stop());
              },
            ),
            const SizedBox(height: 16),
            _PeerReceivePanel(
              active: _mobileServer != null,
              endpoint: _mobileServer == null
                  ? null
                  : '${_mobileServer!.hostAddress}:${_mobileServer!.grpcPort}',
              secondsLeft: _mobileServerSecondsLeft,
              lastReceivedFile: _lastPeerReceivedFile,
              progress: _peerReceiveProgress,
              trustedDevices: _trustedDevices,
              onTrustChanged: (device) {
                unawaited(_setPeerTrusted(device.deviceId, !device.trusted));
              },
              onStart: _startTemporaryMobileServer,
              onStop: () {
                unawaited(_stopTemporaryMobileServer());
              },
            ),
            const SizedBox(height: 16),
            _EventPanel(
              subscribing: _subscribing,
              subscribed: _eventSubscription != null,
              events: _events,
              onSubscribe: _subscribeSelectedServer,
              onUnsubscribe: () {
                unawaited(_unsubscribeEvents());
              },
              onClear: _clearEvents,
            ),
            const SizedBox(height: 16),
            _InboxPanel(
              files: _serverFiles,
              loading: _loadingInbox,
              receiving: _receiving,
              lastReceivedFile: _lastReceivedFile,
              onRefresh: _refreshInbox,
              onReceive: _receiveServerFile,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: OpenFileTransferColors.mint300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                OpenFileTransferMark(size: 56),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '모바일 클라이언트',
                    style: TextStyle(
                      color: OpenFileTransferColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(status),
          ],
        ),
      ),
    );
  }
}

class _DeviceProfilePanel extends StatelessWidget {
  const _DeviceProfilePanel({
    required this.profile,
    required this.controller,
    required this.onSave,
  });

  final DeviceProfile? profile;
  final TextEditingController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _BrandedPanel(
      title: '내 디바이스',
      trailing: OutlinedButton.icon(
        onPressed: onSave,
        icon: const Icon(Icons.save_rounded),
        label: const Text('저장'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '디바이스 이름',
              hintText: '예: 민수 Android',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'UUID ${profile?.deviceId ?? '생성 중'}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: OpenFileTransferColors.teal900),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryPanel extends StatelessWidget {
  const _DiscoveryPanel({
    required this.discovering,
    required this.servers,
    required this.selectedServer,
    required this.selectedSendTargetIds,
    required this.onDiscover,
    required this.onSelectServer,
    required this.onToggleSendTarget,
  });

  final bool discovering;
  final List<DiscoveredServer> servers;
  final DiscoveredServer? selectedServer;
  final Set<String> selectedSendTargetIds;
  final VoidCallback onDiscover;
  final ValueChanged<DiscoveredServer> onSelectServer;
  final ValueChanged<DiscoveredServer> onToggleSendTarget;

  @override
  Widget build(BuildContext context) {
    return _BrandedPanel(
      title: '탐색',
      trailing: FilledButton.icon(
        onPressed: discovering ? null : onDiscover,
        icon: const Icon(Icons.radar_rounded),
        label: Text(discovering ? '찾는 중' : '서버 찾기'),
      ),
      child: servers.isEmpty
          ? const Text('같은 네트워크의 OpenFileTransfer PC 서버가 여기에 표시됩니다.')
          : Column(
              children: servers.map((server) {
                final selected = selectedServer?.deviceId == server.deviceId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ServerTile(
                    server: server,
                    selected: selected,
                    sendTarget: selectedSendTargetIds.contains(server.deviceId),
                    onTap: () => onSelectServer(server),
                    onToggleSendTarget: () => onToggleSendTarget(server),
                  ),
                );
              }).toList(growable: false),
            ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.selected,
    required this.sendTarget,
    required this.onTap,
    required this.onToggleSendTarget,
  });

  final DiscoveredServer server;
  final bool selected;
  final bool sendTarget;
  final VoidCallback onTap;
  final VoidCallback onToggleSendTarget;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? OpenFileTransferColors.mint50 : Colors.white,
          border: Border.all(
            color: selected ? OpenFileTransferColors.teal700 : OpenFileTransferColors.mint300,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : (_isMobilePeerServer(server) ? Icons.smartphone_rounded : Icons.computer_rounded),
                color: OpenFileTransferColors.teal700,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.deviceName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OpenFileTransferColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_isMobilePeerServer(server) ? '모바일 수신 모드' : 'PC/서버'} · ${server.address} · ${server.deviceId}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OpenFileTransferColors.teal900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Checkbox(
                value: sendTarget,
                onChanged: (_) => onToggleSendTarget(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferPanel extends StatelessWidget {
  const _TransferPanel({
    required this.addressController,
    required this.selectedFileName,
    required this.lastReceipt,
    required this.sendResults,
    required this.selectedServer,
    required this.selectedSendTargetCount,
    required this.sending,
    required this.onDiscover,
    required this.onPickFile,
    required this.onSend,
  });

  final TextEditingController addressController;
  final String? selectedFileName;
  final TransferReceipt? lastReceipt;
  final List<_SendTargetResult> sendResults;
  final DiscoveredServer? selectedServer;
  final int selectedSendTargetCount;
  final bool sending;
  final VoidCallback onDiscover;
  final VoidCallback onPickFile;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return _BrandedPanel(
      title: '전송',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: addressController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'PC 서버 주소',
              hintText: '예: 192.168.0.10:39091',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _TransferDetailRow(
            label: '선택 서버',
            value: selectedSendTargetCount > 0
                ? '1:N 전송 대상 $selectedSendTargetCount개'
                : (selectedServer == null
                    ? '직접 입력 또는 서버 찾기'
                    : '${selectedServer!.deviceName} (${selectedServer!.address})'),
          ),
          const SizedBox(height: 8),
          _TransferDetailRow(
            label: '선택 파일',
            value: selectedFileName ?? '없음',
          ),
          if (lastReceipt != null) ...[
            const SizedBox(height: 8),
            _TransferDetailRow(
              label: '서버 저장',
              value: '${lastReceipt!.fileName} · ${lastReceipt!.size} bytes',
            ),
          ],
          if (sendResults.isNotEmpty) ...[
            const SizedBox(height: 10),
            Column(
              children: sendResults.map((result) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: result.success ? OpenFileTransferColors.mint50 : Colors.white,
                      border: Border.all(color: OpenFileTransferColors.mint300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            result.success
                                ? Icons.check_circle_rounded
                                : Icons.error_outline_rounded,
                            color: OpenFileTransferColors.teal700,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  result.target.deviceName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: OpenFileTransferColors.ink,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Builder(
                                  builder: (_) {
                                    final typeLabel = result.target.mobilePeer ? '모바일' : '서버';
                                    return Text(
                                      '$typeLabel · ${result.target.address} · ${result.message}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: OpenFileTransferColors.teal900,
                                        fontSize: 12,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: sending ? null : onPickFile,
                  icon: const Icon(Icons.insert_drive_file_rounded),
                  label: const Text('파일 선택'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: sending ? null : onSend,
                  icon: Icon(iconForTransferDirection(true)),
                  label: Text(
                    sending
                        ? '보내는 중'
                        : (selectedSendTargetCount > 1 ? '1:N 보내기' : '파일 보내기'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onDiscover,
            icon: Icon(iconForTransferDirection(false)),
            label: const Text('받을 서버를 먼저 찾기'),
          ),
        ],
      ),
    );
  }
}

class _TransferDetailRow extends StatelessWidget {
  const _TransferDetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: OpenFileTransferColors.mint50,
        border: Border.all(color: OpenFileTransferColors.mint300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 78,
              child: Text(
                label,
                style: const TextStyle(
                  color: OpenFileTransferColors.teal900,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundTransferPanel extends StatelessWidget {
  const _BackgroundTransferPanel({
    required this.service,
    required this.onStartSend,
    required this.onStartReceive,
    required this.onAdvance,
    required this.onComplete,
    required this.onStop,
  });

  final BackgroundTransferService service;
  final VoidCallback onStartSend;
  final VoidCallback onStartReceive;
  final VoidCallback onAdvance;
  final VoidCallback onComplete;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final snapshot = service.snapshot;
        return _BrandedPanel(
          title: '백그라운드 전송',
          trailing: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              value: snapshot.active ? snapshot.progress : null,
              strokeWidth: 4,
              color: OpenFileTransferColors.teal700,
              backgroundColor: OpenFileTransferColors.mint100,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                snapshot.message,
                style: const TextStyle(
                  color: OpenFileTransferColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: snapshot.active ? snapshot.progress : 0,
                minHeight: 8,
                color: OpenFileTransferColors.teal700,
                backgroundColor: OpenFileTransferColors.mint100,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onStartSend,
                    icon: Icon(iconForTransferDirection(true)),
                    label: const Text('전송 시작'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onStartReceive,
                    icon: Icon(iconForTransferDirection(false)),
                    label: const Text('수신 시작'),
                  ),
                  OutlinedButton.icon(
                    onPressed: snapshot.active ? onAdvance : null,
                    icon: const Icon(Icons.trending_up_rounded),
                    label: Text('${snapshot.percent}%'),
                  ),
                  FilledButton.icon(
                    onPressed: snapshot.active ? onComplete : null,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('완료'),
                  ),
                  TextButton.icon(
                    onPressed: snapshot.active ? onStop : null,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('중지'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InboxPanel extends StatelessWidget {
  const _InboxPanel({
    required this.files,
    required this.loading,
    required this.receiving,
    required this.lastReceivedFile,
    required this.onRefresh,
    required this.onReceive,
  });

  final List<FileEntry> files;
  final bool loading;
  final bool receiving;
  final ReceivedFileResult? lastReceivedFile;
  final VoidCallback onRefresh;
  final ValueChanged<FileEntry> onReceive;

  @override
  Widget build(BuildContext context) {
    return _BrandedPanel(
      title: '서버 수신함',
      trailing: OutlinedButton.icon(
        onPressed: loading ? null : onRefresh,
        icon: const Icon(Icons.inbox_rounded),
        label: Text(loading ? '조회 중' : '새로고침'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lastReceivedFile != null) ...[
            _TransferDetailRow(
              label: '최근 수신',
              value: '${lastReceivedFile!.fileName} · ${lastReceivedFile!.size} bytes',
            ),
            const SizedBox(height: 10),
          ],
          if (files.isEmpty)
            const Text('연결한 서버의 수신 파일 목록이 여기에 표시됩니다.')
          else
            Column(
              children: files.map((file) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: OpenFileTransferColors.mint50,
                      border: Border.all(color: OpenFileTransferColors.mint300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.insert_drive_file_rounded,
                            color: OpenFileTransferColors.teal700,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  file.fileName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: OpenFileTransferColors.ink,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${file.size} bytes · ${file.sha256Hex}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: OpenFileTransferColors.teal900,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: receiving ? null : () => onReceive(file),
                            icon: Icon(iconForTransferDirection(false)),
                            label: Text(receiving ? '수신 중' : '받기'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _PeerReceivePanel extends StatelessWidget {
  const _PeerReceivePanel({
    required this.active,
    required this.endpoint,
    required this.secondsLeft,
    required this.lastReceivedFile,
    required this.progress,
    required this.trustedDevices,
    required this.onTrustChanged,
    required this.onStart,
    required this.onStop,
  });

  final bool active;
  final String? endpoint;
  final int secondsLeft;
  final MobileReceivedFile? lastReceivedFile;
  final MobileTransferProgress? progress;
  final List<TrustedDevice> trustedDevices;
  final ValueChanged<TrustedDevice> onTrustChanged;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final minutes = (secondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (secondsLeft % 60).toString().padLeft(2, '0');
    return _BrandedPanel(
      title: '모바일 수신 모드',
      trailing: active
          ? OutlinedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_rounded),
              label: const Text('중지'),
            )
          : FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.mobile_friendly_rounded),
              label: const Text('10분 열기'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TransferDetailRow(
            label: '상태',
            value: active ? '수신 대기 중 · $minutes:$seconds' : '꺼짐',
          ),
          const SizedBox(height: 8),
          _TransferDetailRow(
            label: '주소',
            value: endpoint ?? '수신 모드를 켜면 같은 네트워크에 표시됩니다.',
          ),
          if (lastReceivedFile != null) ...[
            const SizedBox(height: 8),
            _TransferDetailRow(
              label: '최근 수신',
              value: '${lastReceivedFile!.fileName} · ${lastReceivedFile!.size} bytes',
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 12),
            Text(
              '${progress!.peerName} · ${progress!.fileName} · ${(progress!.progress * 100).round()}%',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: OpenFileTransferColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress!.progress,
              minHeight: 8,
              color: OpenFileTransferColors.teal700,
              backgroundColor: OpenFileTransferColors.mint100,
              borderRadius: BorderRadius.circular(8),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            '미승인 모바일은 파일을 주고받기 전에 확인 창을 띄우고, '
            '항상 허용한 디바이스는 바로 통과합니다.',
            style: TextStyle(color: OpenFileTransferColors.teal900),
          ),
          const SizedBox(height: 12),
          if (trustedDevices.isEmpty)
            const Text('아직 발견되거나 승인된 모바일 디바이스가 없습니다.')
          else
            Column(
              children: trustedDevices.map((device) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: device.trusted ? OpenFileTransferColors.mint50 : Colors.white,
                      border: Border.all(color: OpenFileTransferColors.mint300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            device.trusted
                                ? Icons.verified_user_rounded
                                : Icons.person_search_rounded,
                            color: OpenFileTransferColors.teal700,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  device.deviceName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: OpenFileTransferColors.ink,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Builder(
                                  builder: (_) {
                                    final trustLabel = device.trusted ? '항상 허용' : '확인 필요';
                                    return Text(
                                      '$trustLabel · ${device.transferCount}회 수신 · ${device.deviceId}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: OpenFileTransferColors.teal900,
                                        fontSize: 12,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => onTrustChanged(device),
                            icon: Icon(
                              device.trusted
                                  ? Icons.lock_open_rounded
                                  : Icons.done_rounded,
                            ),
                            label: Text(device.trusted ? '해제' : '허용'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _EventPanel extends StatelessWidget {
  const _EventPanel({
    required this.subscribing,
    required this.subscribed,
    required this.events,
    required this.onSubscribe,
    required this.onUnsubscribe,
    required this.onClear,
  });

  final bool subscribing;
  final bool subscribed;
  final List<ServerEvent> events;
  final VoidCallback onSubscribe;
  final VoidCallback onUnsubscribe;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _BrandedPanel(
      title: '서버 이벤트',
      trailing: Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: subscribing ? null : (subscribed ? onUnsubscribe : onSubscribe),
            icon: Icon(subscribed ? Icons.notifications_off_rounded : Icons.notifications_active_rounded),
            label: Text(subscribing ? '구독 중' : (subscribed ? '해제' : '구독')),
          ),
          OutlinedButton.icon(
            onPressed: events.isEmpty ? null : onClear,
            icon: const Icon(Icons.clear_rounded),
            label: const Text('지우기'),
          ),
        ],
      ),
      child: events.isEmpty
          ? const Text(
              'PC 서버를 선택하고 구독하면 파일 수신, 서버 메시지, 연결 상태 이벤트가 여기에 표시됩니다.',
            )
          : Column(
              children: events.reversed.take(10).map((event) {
                final fileText = event.file?.fileName == null ? '' : ' · ${event.file!.fileName}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TransferDetailRow(
                    label: event.type.isEmpty ? 'event' : event.type,
                    value: '${event.message}$fileText',
                  ),
                );
              }).toList(growable: false),
            ),
    );
  }
}

class _BrandedPanel extends StatelessWidget {
  const _BrandedPanel({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: OpenFileTransferColors.mint300),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: OpenFileTransferColors.teal700.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: OpenFileTransferColors.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
