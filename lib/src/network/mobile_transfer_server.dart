import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:grpc/grpc.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../discovery/ssdp_discovery_client.dart';
import '../protocol/transfer_messages.dart';

const _sessionTtl = Duration(minutes: 10);
final _hkdfSalt = Uint8List.fromList('openfiletransfer-v1-session'.codeUnits);
final _hkdfInfo = Uint8List.fromList('openfiletransfer-file-payload'.codeUnits);
final _x25519SpkiPrefix = Uint8List.fromList(<int>[
  0x30,
  0x2a,
  0x30,
  0x05,
  0x06,
  0x03,
  0x2b,
  0x65,
  0x6e,
  0x03,
  0x21,
  0x00,
]);

class MobileReceivedFile {
  const MobileReceivedFile({
    required this.fileName,
    required this.outputPath,
    required this.size,
    required this.sha256Hex,
  });

  final String fileName;
  final String outputPath;
  final int size;
  final String sha256Hex;
}

class ActiveMobileTransferServer {
  ActiveMobileTransferServer({
    required this.deviceId,
    required this.deviceName,
    required this.receiveDirectory,
    required this.ttl,
    this.onFileReceived,
  });

  final String deviceId;
  final String deviceName;
  final String receiveDirectory;
  final Duration ttl;
  final void Function(MobileReceivedFile file)? onFileReceived;

  late final Server _grpcServer;
  HttpServer? _descriptorServer;
  RawDatagramSocket? _ssdpSocket;
  Timer? _stopTimer;
  int? _grpcPort;
  int? _descriptorPort;
  String? _hostAddress;

  int? get grpcPort => _grpcPort;
  int? get descriptorPort => _descriptorPort;
  String? get hostAddress => _hostAddress;
  String? get descriptorUrl {
    final host = _hostAddress;
    final port = _descriptorPort;
    if (host == null || port == null) {
      return null;
    }
    return 'http://$host:$port/openfiletransfer.json';
  }

  Future<void> start() async {
    await Directory(receiveDirectory).create(recursive: true);
    _hostAddress = await _localIpv4Address();
    _grpcServer = Server.create(
      services: <Service>[
        _MobileTransferService(
          deviceId: deviceId,
          deviceName: deviceName,
          receiveDirectory: receiveDirectory,
          onFileReceived: onFileReceived,
        ),
      ],
    );
    await _grpcServer.serve(address: InternetAddress.anyIPv4, port: 0);
    _grpcPort = _grpcServer.port;
    await _startDescriptorServer();
    await _startSsdpResponder();
    _stopTimer = Timer(ttl, () {
      unawaited(stop());
    });
  }

  Future<void> stop() async {
    _stopTimer?.cancel();
    _stopTimer = null;
    _ssdpSocket?.close();
    _ssdpSocket = null;
    await _descriptorServer?.close(force: true);
    _descriptorServer = null;
    await _grpcServer.shutdown();
  }

  Future<void> _startDescriptorServer() async {
    _descriptorServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _descriptorPort = _descriptorServer!.port;
    _descriptorServer!.listen((request) {
      final host = _hostAddress ?? '127.0.0.1';
      final body = jsonEncode(<String, Object?>{
        'serviceType': openFileTransferServiceType,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'grpcHost': host,
        'grpcPort': _grpcPort,
        'capabilities': <String>[
          'mobile-temporary-server',
          'grpc',
          'send-file',
          'aes-256-gcm',
        ],
      });
      request.response.headers.contentType = ContentType.json;
      request.response.write(body);
      unawaited(request.response.close());
    });
  }

  Future<void> _startSsdpResponder() async {
    _ssdpSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      1900,
      reuseAddress: true,
      reusePort: true,
    );
    _ssdpSocket!
      ..broadcastEnabled = true
      ..multicastHops = 2
      ..joinMulticast(InternetAddress('239.255.255.250'));
    _ssdpSocket!.listen((event) {
      if (event != RawSocketEvent.read) {
        return;
      }
      Datagram? datagram;
      while ((datagram = _ssdpSocket!.receive()) != null) {
        final current = datagram!;
        final message = utf8.decode(current.data, allowMalformed: true).toLowerCase();
        if (!message.contains('m-search') || !message.contains(openFileTransferServiceType)) {
          continue;
        }
        final location = descriptorUrl;
        if (location == null) {
          continue;
        }
        final response = [
          'HTTP/1.1 200 OK',
          'CACHE-CONTROL: max-age=60',
          'EXT:',
          'ST: $openFileTransferServiceType',
          'USN: uuid:$deviceId::$openFileTransferServiceType',
          'LOCATION: $location',
          '',
          '',
        ].join('\r\n');
        _ssdpSocket!.send(utf8.encode(response), current.address, current.port);
      }
    });
  }

  Future<String> _localIpv4Address() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) {
          return address.address;
        }
      }
    }
    return '127.0.0.1';
  }
}

class _MobileSession {
  const _MobileSession({
    required this.sessionKey,
    required this.clientDeviceId,
    required this.clientName,
    required this.expiresAt,
  });

  final SecretKey sessionKey;
  final String clientDeviceId;
  final String clientName;
  final DateTime expiresAt;
}

class _MobileTransferService extends Service {
  _MobileTransferService({
    required this.deviceId,
    required this.deviceName,
    required this.receiveDirectory,
    required this.onFileReceived,
  }) {
    $addMethod(ServiceMethod<HandshakeRequest, HandshakeResponse>(
      'Handshake',
      handshake,
      false,
      false,
      HandshakeRequest.fromBuffer,
      (response) => response.writeToBuffer(),
    ));
    $addMethod(ServiceMethod<FileChunk, TransferReceipt>(
      'SendFile',
      sendFile,
      true,
      false,
      FileChunk.fromBuffer,
      (response) => response.writeToBuffer(),
    ));
    $addMethod(ServiceMethod<ListFilesRequest, ListFilesResponse>(
      'ListFiles',
      listFiles,
      false,
      false,
      ListFilesRequest.fromBuffer,
      (response) => response.writeToBuffer(),
    ));
    $addMethod(ServiceMethod<EventSubscription, ServerEvent>(
      'SubscribeEvents',
      subscribeEvents,
      false,
      true,
      EventSubscription.fromBuffer,
      (response) => response.writeToBuffer(),
    ));
  }

  final String deviceId;
  final String deviceName;
  final String receiveDirectory;
  final void Function(MobileReceivedFile file)? onFileReceived;
  final Map<String, _MobileSession> _sessions = <String, _MobileSession>{};
  final List<FileEntry> _files = <FileEntry>[];

  @override
  String get $name => 'openfiletransfer.v1.TransferService';

  Future<HandshakeResponse> handshake(ServiceCall call, HandshakeRequest request) async {
    final keyAlgorithm = X25519();
    final keyPair = await keyAlgorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final sharedSecret = await keyAlgorithm.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(
        _fromX25519Spki(request.clientPublicKey),
        type: KeyPairType.x25519,
      ),
    );
    final sessionKey = await Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    ).deriveKey(
      secretKey: sharedSecret,
      nonce: _hkdfSalt,
      info: _hkdfInfo,
    );
    final sessionId = const Uuid().v4();
    final expiresAt = DateTime.now().add(_sessionTtl);
    _sessions[sessionId] = _MobileSession(
      sessionKey: sessionKey,
      clientDeviceId: request.clientDeviceId,
      clientName: request.clientName,
      expiresAt: expiresAt,
    );
    return HandshakeResponse(
      sessionId: sessionId,
      serverDeviceId: deviceId,
      serverName: deviceName,
      serverPublicKey: _toX25519Spki(publicKey.bytes),
      selectedCipher: openFileTransferCipher,
      expiresAtUnixTimeMs: expiresAt.millisecondsSinceEpoch,
    );
  }

  Future<TransferReceipt> sendFile(ServiceCall call, Stream<FileChunk> request) async {
    String? transferId;
    String? fileName;
    IOSink? sink;
    String? outputPath;
    var size = 0;
    _MobileSession? session;
    final digestSink = AccumulatorSink<crypto.Digest>();
    final hashInput = crypto.sha256.startChunkedConversion(digestSink);

    try {
      await for (final chunk in request) {
        session ??= _requireSession(chunk.sessionId);
        transferId ??= chunk.transferId.isEmpty ? const Uuid().v4() : chunk.transferId;
        fileName ??= p.basename(chunk.fileName.isEmpty ? 'mobile-transfer.bin' : chunk.fileName);
        outputPath ??= await _availableOutputPath(receiveDirectory, fileName);
        sink ??= File(outputPath).openWrite();
        final plain = chunk.encrypted
            ? await AesGcm.with256bits().decrypt(
                SecretBox(chunk.data, nonce: chunk.nonce, mac: Mac(chunk.authTag)),
                secretKey: session.sessionKey,
              )
            : chunk.data;
        sink.add(plain);
        hashInput.add(plain);
        size += plain.length;
      }
    } finally {
      await sink?.close();
      hashInput.close();
    }

    if (transferId == null || fileName == null || outputPath == null) {
      throw GrpcError.invalidArgument('파일 chunk를 받지 못했습니다.');
    }
    final sha256Hex = digestSink.events.single.toString();
    final fileId = const Uuid().v4();
    final entry = FileEntry(
      fileId: fileId,
      fileName: fileName,
      size: size,
      sha256Hex: sha256Hex,
      receivedAtUnixTimeMs: DateTime.now().millisecondsSinceEpoch,
    );
    _files.insert(0, entry);
    onFileReceived?.call(
      MobileReceivedFile(
        fileName: fileName,
        outputPath: outputPath,
        size: size,
        sha256Hex: sha256Hex,
      ),
    );
    return TransferReceipt(
      transferId: transferId,
      fileId: fileId,
      fileName: fileName,
      size: size,
      sha256Hex: sha256Hex,
      stored: true,
    );
  }

  Future<ListFilesResponse> listFiles(ServiceCall call, ListFilesRequest request) async {
    _requireSession(request.sessionId);
    return ListFilesResponse(files: List<FileEntry>.unmodifiable(_files));
  }

  Stream<ServerEvent> subscribeEvents(ServiceCall call, EventSubscription request) async* {
    _requireSession(request.sessionId);
    yield ServerEvent(
      eventId: const Uuid().v4(),
      type: 'server_message',
      unixTimeMs: DateTime.now().millisecondsSinceEpoch,
      message: '모바일 임시 수신 서버 연결됨',
      sessionId: request.sessionId,
      peerDeviceId: deviceId,
      peerName: deviceName,
      file: null,
    );
  }

  _MobileSession _requireSession(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null || session.expiresAt.isBefore(DateTime.now())) {
      throw GrpcError.unauthenticated('세션이 없거나 만료되었습니다.');
    }
    return session;
  }

  Future<String> _availableOutputPath(String directory, String fileName) async {
    final safeName = p.basename(fileName);
    final extension = p.extension(safeName);
    final baseName = p.basenameWithoutExtension(safeName);
    var candidate = p.join(directory, safeName);
    var index = 1;
    while (await File(candidate).exists()) {
      candidate = p.join(directory, '$baseName-$index$extension');
      index += 1;
    }
    return candidate;
  }

  List<int> _toX25519Spki(List<int> rawPublicKey) {
    if (rawPublicKey.length != 32) {
      throw ArgumentError('X25519 public key는 32 bytes여야 합니다.');
    }
    return <int>[..._x25519SpkiPrefix, ...rawPublicKey];
  }

  List<int> _fromX25519Spki(List<int> spkiPublicKey) {
    if (spkiPublicKey.length == 32) {
      return spkiPublicKey;
    }
    if (spkiPublicKey.length != _x25519SpkiPrefix.length + 32) {
      throw const FormatException('알 수 없는 X25519 public key 형식입니다.');
    }
    for (var index = 0; index < _x25519SpkiPrefix.length; index += 1) {
      if (spkiPublicKey[index] != _x25519SpkiPrefix[index]) {
        throw const FormatException('X25519 SPKI prefix가 일치하지 않습니다.');
      }
    }
    return spkiPublicKey.sublist(_x25519SpkiPrefix.length);
  }
}
