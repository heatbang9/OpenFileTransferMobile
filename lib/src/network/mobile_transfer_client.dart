import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:grpc/grpc.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../protocol/transfer_messages.dart';

export '../protocol/transfer_messages.dart' show ServerEvent, TransferReceipt;

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

class OpenFileTransferAddress {
  const OpenFileTransferAddress({
    required this.host,
    required this.port,
  });

  final String host;
  final int port;

  static OpenFileTransferAddress parse(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed.contains('://') ? trimmed : 'grpc://$trimmed');
    if (uri == null || uri.host.isEmpty) {
      throw const FormatException('서버 주소는 host:port 형식이어야 합니다.');
    }
    return OpenFileTransferAddress(
      host: uri.host,
      port: uri.hasPort ? uri.port : 39091,
    );
  }
}

class OpenFileTransferSession {
  const OpenFileTransferSession({
    required this.sessionId,
    required this.serverName,
    required this.sessionKey,
  });

  final String sessionId;
  final String serverName;
  final SecretKey sessionKey;
}

class OpenFileTransferProgress {
  const OpenFileTransferProgress({
    required this.sentBytes,
    required this.totalBytes,
    required this.progress,
  });

  final int sentBytes;
  final int totalBytes;
  final double progress;
}

class OpenFileTransferGrpcClient extends Client {
  OpenFileTransferGrpcClient(super.channel);

  static final ClientMethod<HandshakeRequest, HandshakeResponse> _handshake =
      ClientMethod<HandshakeRequest, HandshakeResponse>(
    '/openfiletransfer.v1.TransferService/Handshake',
    (request) => request.writeToBuffer(),
    HandshakeResponse.fromBuffer,
  );

  static final ClientMethod<FileChunk, TransferReceipt> _sendFile =
      ClientMethod<FileChunk, TransferReceipt>(
    '/openfiletransfer.v1.TransferService/SendFile',
    (request) => request.writeToBuffer(),
    TransferReceipt.fromBuffer,
  );

  static final ClientMethod<EventSubscription, ServerEvent> _subscribeEvents =
      ClientMethod<EventSubscription, ServerEvent>(
    '/openfiletransfer.v1.TransferService/SubscribeEvents',
    (request) => request.writeToBuffer(),
    ServerEvent.fromBuffer,
  );

  ResponseFuture<HandshakeResponse> handshake(HandshakeRequest request) {
    return $createUnaryCall(_handshake, request);
  }

  ResponseFuture<TransferReceipt> sendFile(Stream<FileChunk> request) {
    return $createStreamingCall(_sendFile, request).single;
  }

  ResponseStream<ServerEvent> subscribeEvents(EventSubscription request) {
    return $createStreamingCall(_subscribeEvents, Stream<EventSubscription>.value(request));
  }
}

class MobileTransferClient {
  MobileTransferClient({
    required String address,
    String? clientDeviceId,
    this.clientName = 'OpenFileTransfer Mobile',
  })  : parsedAddress = OpenFileTransferAddress.parse(address),
        clientDeviceId = clientDeviceId ?? const Uuid().v4() {
    _channel = ClientChannel(
      parsedAddress.host,
      port: parsedAddress.port,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
        idleTimeout: Duration(seconds: 30),
      ),
    );
    _grpcClient = OpenFileTransferGrpcClient(_channel);
  }

  final OpenFileTransferAddress parsedAddress;
  final String clientDeviceId;
  final String clientName;
  late final ClientChannel _channel;
  late final OpenFileTransferGrpcClient _grpcClient;

  Future<OpenFileTransferSession> handshake() async {
    final keyAlgorithm = X25519();
    final keyPair = await keyAlgorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final response = await _grpcClient.handshake(
      HandshakeRequest(
        clientDeviceId: clientDeviceId,
        clientName: clientName,
        clientPublicKey: _toX25519Spki(publicKey.bytes),
        supportedCiphers: const [openFileTransferCipher],
      ),
    );

    if (response.selectedCipher != openFileTransferCipher) {
      throw StateError('지원하지 않는 cipher입니다: ${response.selectedCipher}');
    }
    final sharedSecret = await keyAlgorithm.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(
        _fromX25519Spki(response.serverPublicKey),
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

    return OpenFileTransferSession(
      sessionId: response.sessionId,
      serverName: response.serverName,
      sessionKey: sessionKey,
    );
  }

  Future<TransferReceipt> sendFile(
    String filePath, {
    void Function(OpenFileTransferProgress progress)? onProgress,
  }) async {
    final session = await handshake();
    final file = File(filePath);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw ArgumentError('파일만 전송할 수 있습니다: $filePath');
    }

    final totalSize = stat.size;
    final fileName = p.basename(filePath);
    final transferId = const Uuid().v4();
    final digestSink = AccumulatorSink<crypto.Digest>();
    final hashInput = crypto.sha256.startChunkedConversion(digestSink);
    var offset = 0;

    final stream = file.openRead().asyncMap((plain) async {
      hashInput.add(plain);
      final encrypted = await _encryptChunk(session.sessionKey, plain);
      final chunk = FileChunk(
        sessionId: session.sessionId,
        transferId: transferId,
        fileName: fileName,
        totalSize: totalSize,
        offset: offset,
        nonce: encrypted.nonce,
        data: encrypted.cipherText,
        authTag: encrypted.mac.bytes,
        encrypted: true,
        sha256Hex: '',
      );
      offset += plain.length;
      onProgress?.call(
        OpenFileTransferProgress(
          sentBytes: offset,
          totalBytes: totalSize,
          progress: totalSize == 0 ? 1 : offset / totalSize,
        ),
      );
      return chunk;
    });

    final receipt = await _grpcClient.sendFile(stream);
    hashInput.close();
    final localSha256 = digestSink.events.single.toString();
    if (receipt.sha256Hex.isNotEmpty && receipt.sha256Hex != localSha256) {
      throw StateError('전송 해시가 일치하지 않습니다.');
    }
    return receipt;
  }

  Future<MobileEventSubscription> subscribeEvents({
    void Function(ServerEvent event)? onEvent,
    void Function(Object error)? onError,
  }) async {
    final session = await handshake();
    final stream = _grpcClient.subscribeEvents(
      EventSubscription(
        sessionId: session.sessionId,
        clientDeviceId: clientDeviceId,
        clientName: clientName,
        eventTypes: const <String>[],
      ),
    );
    final subscription = stream.listen(
      onEvent,
      onError: onError,
      cancelOnError: false,
    );
    return MobileEventSubscription(
      session: session,
      subscription: subscription,
    );
  }

  Future<void> close() => _channel.shutdown();

  Future<SecretBox> _encryptChunk(SecretKey sessionKey, List<int> plain) {
    return AesGcm.with256bits().encrypt(
      plain,
      secretKey: sessionKey,
      nonce: _randomNonce(),
    );
  }

  List<int> _randomNonce() {
    final random = Random.secure();
    return List<int>.generate(12, (_) => random.nextInt(256));
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

class MobileEventSubscription {
  const MobileEventSubscription({
    required this.session,
    required this.subscription,
  });

  final OpenFileTransferSession session;
  final StreamSubscription<ServerEvent> subscription;

  Future<void> cancel() => subscription.cancel();
}
