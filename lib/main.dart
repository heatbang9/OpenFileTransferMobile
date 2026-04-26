import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'src/brand/open_file_transfer_brand.dart';
import 'src/device/device_profile_store.dart';
import 'src/discovery/ssdp_discovery_client.dart';
import 'src/network/mobile_transfer_client.dart';
import 'src/transfer/background_transfer_service.dart';

final BackgroundTransferService _backgroundTransferService = BackgroundTransferService();
final DeviceProfileStore _deviceProfileStore = DeviceProfileStore();

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
  MobileTransferClient? _eventClient;
  MobileEventSubscription? _eventSubscription;
  final List<ServerEvent> _events = <ServerEvent>[];
  String? _selectedFilePath;
  String? _selectedFileName;
  TransferReceipt? _lastReceipt;
  bool _discovering = false;
  bool _subscribing = false;
  bool _sending = false;

  void _markPending(String text) {
    setState(() {
      _status = text;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadDeviceProfile();
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
      _status = '${server.deviceName}에 연결할 준비가 되었습니다.';
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

  Future<void> _sendSelectedFile() async {
    final filePath = _selectedFilePath;
    final fileName = _selectedFileName;
    final address = _addressController.text.trim();
    if (filePath == null || fileName == null) {
      _markPending('먼저 전송할 파일을 선택하세요.');
      return;
    }
    if (address.isEmpty) {
      _markPending('PC 서버 주소를 입력하세요.');
      return;
    }

    setState(() {
      _sending = true;
      _lastReceipt = null;
      _status = 'PC 서버와 Handshake 중';
    });
    MobileTransferClient? client;
    try {
      await _backgroundTransferService.startTransfer(
        direction: TransferDirection.sending,
        fileName: fileName,
      );
      final profile = _deviceProfile ?? await _deviceProfileStore.load();
      client = MobileTransferClient(
        address: address,
        clientDeviceId: profile.deviceId,
        clientName: profile.deviceName,
      );
      final receipt = await client.sendFile(
        filePath,
        onProgress: (progress) {
          unawaited(_backgroundTransferService.updateProgress(progress.progress));
          if (!mounted) {
            return;
          }
          setState(() {
            _status = '파일 전송 중 · ${(progress.progress * 100).round()}%';
          });
        },
      );
      await _backgroundTransferService.completeTransfer();
      if (!mounted) {
        return;
      }
      setState(() {
        _lastReceipt = receipt;
        _status = '${receipt.fileName} 전송 완료';
      });
    } catch (error) {
      await _backgroundTransferService.stop();
      if (!mounted) {
        return;
      }
      setStatusWithError(error);
    } finally {
      await client?.close();
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  void setStatusWithError(Object error) {
    setState(() {
      _status = '전송 실패: $error';
    });
  }

  @override
  void dispose() {
    unawaited(_unsubscribeEvents(updateStatus: false));
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
              onDiscover: _discoverServers,
              onSelectServer: _selectServer,
            ),
            const SizedBox(height: 16),
            _TransferPanel(
              addressController: _addressController,
              selectedFileName: _selectedFileName,
              lastReceipt: _lastReceipt,
              selectedServer: _selectedServer,
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
            const _InboxPanel(),
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
    required this.onDiscover,
    required this.onSelectServer,
  });

  final bool discovering;
  final List<DiscoveredServer> servers;
  final DiscoveredServer? selectedServer;
  final VoidCallback onDiscover;
  final ValueChanged<DiscoveredServer> onSelectServer;

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
                    onTap: () => onSelectServer(server),
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
    required this.onTap,
  });

  final DiscoveredServer server;
  final bool selected;
  final VoidCallback onTap;

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
                selected ? Icons.check_circle_rounded : Icons.computer_rounded,
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
                      '${server.address} · ${server.deviceId}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OpenFileTransferColors.teal900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
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
    required this.selectedServer,
    required this.sending,
    required this.onDiscover,
    required this.onPickFile,
    required this.onSend,
  });

  final TextEditingController addressController;
  final String? selectedFileName;
  final TransferReceipt? lastReceipt;
  final DiscoveredServer? selectedServer;
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
            value: selectedServer == null
                ? '직접 입력 또는 서버 찾기'
                : '${selectedServer!.deviceName} (${selectedServer!.address})',
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
                  label: Text(sending ? '보내는 중' : '파일 보내기'),
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
  const _InboxPanel();

  @override
  Widget build(BuildContext context) {
    return _BrandedPanel(
      title: '서버 수신함',
      trailing: OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.inbox_rounded),
        label: const Text('새로고침'),
      ),
      child: const Text('연결한 서버의 수신 파일 목록이 여기에 표시됩니다.'),
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
