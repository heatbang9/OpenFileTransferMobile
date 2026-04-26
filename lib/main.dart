import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'src/brand/open_file_transfer_brand.dart';
import 'src/network/mobile_transfer_client.dart';
import 'src/transfer/background_transfer_service.dart';

final BackgroundTransferService _backgroundTransferService = BackgroundTransferService();

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
  String _status = '서버를 찾을 준비가 되었습니다.';
  String? _selectedFilePath;
  String? _selectedFileName;
  TransferReceipt? _lastReceipt;
  bool _sending = false;

  void _markPending(String text) {
    setState(() {
      _status = text;
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
      client = MobileTransferClient(address: address);
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
    _addressController.dispose();
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
            _DiscoveryPanel(
              onDiscover: () => _markPending('SSDP 탐색 구현 대기 중'),
            ),
            const SizedBox(height: 16),
            _TransferPanel(
              addressController: _addressController,
              selectedFileName: _selectedFileName,
              lastReceipt: _lastReceipt,
              sending: _sending,
              onDiscover: () => _markPending('SSDP 자동 탐색은 다음 단계입니다. 지금은 PC 서버 주소를 직접 입력하세요.'),
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
            const _DeviceListPanel(),
            const SizedBox(height: 16),
            const _EventPanel(),
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

class _DiscoveryPanel extends StatelessWidget {
  const _DiscoveryPanel({required this.onDiscover});

  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    return _BrandedPanel(
      title: '탐색',
      trailing: FilledButton.icon(
        onPressed: onDiscover,
        icon: const Icon(Icons.radar_rounded),
        label: const Text('서버 찾기'),
      ),
      child: const Text('같은 네트워크의 PC 서버가 여기에 표시됩니다.'),
    );
  }
}

class _TransferPanel extends StatelessWidget {
  const _TransferPanel({
    required this.addressController,
    required this.selectedFileName,
    required this.lastReceipt,
    required this.sending,
    required this.onDiscover,
    required this.onPickFile,
    required this.onSend,
  });

  final TextEditingController addressController;
  final String? selectedFileName;
  final TransferReceipt? lastReceipt;
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

class _DeviceListPanel extends StatelessWidget {
  const _DeviceListPanel();

  @override
  Widget build(BuildContext context) {
    return const _BrandedPanel(
      title: '서버 목록',
      child: Text('찾은 서버가 여기에 표시됩니다.'),
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
  const _EventPanel();

  @override
  Widget build(BuildContext context) {
    return _BrandedPanel(
      title: '서버 이벤트',
      trailing: OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.notifications_active_rounded),
        label: const Text('구독'),
      ),
      child: const Text(
        'PC 서버 연결 후 SubscribeEvents 스트림을 유지하면 파일 수신, 서버 메시지, 연결 상태 이벤트가 여기에 표시됩니다.',
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
