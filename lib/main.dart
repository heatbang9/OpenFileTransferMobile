import 'package:flutter/material.dart';

void main() {
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
          seedColor: const Color(0xff176b87),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const DeviceDiscoveryPage(),
    );
  }
}

class DeviceDiscoveryPage extends StatefulWidget {
  const DeviceDiscoveryPage({super.key});

  @override
  State<DeviceDiscoveryPage> createState() => _DeviceDiscoveryPageState();
}

class _DeviceDiscoveryPageState extends State<DeviceDiscoveryPage> {
  String _status = '서버를 찾을 준비가 되었습니다.';

  void _markPending(String text) {
    setState(() {
      _status = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenFileTransfer'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusPanel(status: _status),
            const SizedBox(height: 16),
            _ActionPanel(
              onDiscover: () => _markPending('SSDP 탐색 구현 대기 중'),
              onPickFile: () => _markPending('파일 선택 구현 대기 중'),
              onSend: () => _markPending('gRPC 전송 구현 대기 중'),
            ),
            const SizedBox(height: 16),
            const _DeviceListPanel(),
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
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '모바일 클라이언트',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(status),
          ],
        ),
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.onDiscover,
    required this.onPickFile,
    required this.onSend,
  });

  final VoidCallback onDiscover;
  final VoidCallback onPickFile;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onDiscover,
          icon: const Icon(Icons.search),
          label: const Text('서버 찾기'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onPickFile,
          icon: const Icon(Icons.attach_file),
          label: const Text('파일 선택'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onSend,
          icon: const Icon(Icons.upload_file),
          label: const Text('파일 보내기'),
        ),
      ],
    );
  }
}

class _DeviceListPanel extends StatelessWidget {
  const _DeviceListPanel();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text('찾은 서버가 여기에 표시됩니다.'),
      ),
    );
  }
}

