import 'protobuf_wire.dart';

const openFileTransferCipher = 'x25519-hkdf-sha256+aes-256-gcm';

class HandshakeRequest {
  const HandshakeRequest({
    required this.clientDeviceId,
    required this.clientName,
    required this.clientPublicKey,
    required this.supportedCiphers,
  });

  final String clientDeviceId;
  final String clientName;
  final List<int> clientPublicKey;
  final List<String> supportedCiphers;

  List<int> writeToBuffer() {
    final writer = ProtoWriter()
      ..writeString(1, clientDeviceId)
      ..writeString(2, clientName)
      ..writeBytes(3, clientPublicKey);
    for (final cipher in supportedCiphers) {
      writer.writeString(4, cipher);
    }
    return writer.takeBytes();
  }
}

class HandshakeResponse {
  const HandshakeResponse({
    required this.sessionId,
    required this.serverDeviceId,
    required this.serverName,
    required this.serverPublicKey,
    required this.selectedCipher,
    required this.expiresAtUnixTimeMs,
  });

  final String sessionId;
  final String serverDeviceId;
  final String serverName;
  final List<int> serverPublicKey;
  final String selectedCipher;
  final int expiresAtUnixTimeMs;

  static HandshakeResponse fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var sessionId = '';
    var serverDeviceId = '';
    var serverName = '';
    var serverPublicKey = <int>[];
    var selectedCipher = '';
    var expiresAtUnixTimeMs = 0;

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      final field = tag >> 3;
      final wireType = tag & 7;
      switch (field) {
        case 1:
          sessionId = reader.readString();
          break;
        case 2:
          serverDeviceId = reader.readString();
          break;
        case 3:
          serverName = reader.readString();
          break;
        case 4:
          serverPublicKey = reader.readLengthDelimited();
          break;
        case 5:
          selectedCipher = reader.readString();
          break;
        case 6:
          expiresAtUnixTimeMs = reader.readVarint();
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return HandshakeResponse(
      sessionId: sessionId,
      serverDeviceId: serverDeviceId,
      serverName: serverName,
      serverPublicKey: serverPublicKey,
      selectedCipher: selectedCipher,
      expiresAtUnixTimeMs: expiresAtUnixTimeMs,
    );
  }
}

class FileChunk {
  const FileChunk({
    required this.sessionId,
    required this.transferId,
    required this.fileName,
    required this.totalSize,
    required this.offset,
    required this.nonce,
    required this.data,
    required this.authTag,
    required this.encrypted,
    required this.sha256Hex,
  });

  final String sessionId;
  final String transferId;
  final String fileName;
  final int totalSize;
  final int offset;
  final List<int> nonce;
  final List<int> data;
  final List<int> authTag;
  final bool encrypted;
  final String sha256Hex;

  List<int> writeToBuffer() {
    return (ProtoWriter()
          ..writeString(1, sessionId)
          ..writeString(2, transferId)
          ..writeString(3, fileName)
          ..writeUint64(4, totalSize)
          ..writeUint64(5, offset)
          ..writeBytes(6, nonce)
          ..writeBytes(7, data)
          ..writeBytes(8, authTag)
          ..writeBool(9, encrypted)
          ..writeString(10, sha256Hex))
        .takeBytes();
  }
}

class TransferReceipt {
  const TransferReceipt({
    required this.transferId,
    required this.fileId,
    required this.fileName,
    required this.size,
    required this.sha256Hex,
    required this.stored,
  });

  final String transferId;
  final String fileId;
  final String fileName;
  final int size;
  final String sha256Hex;
  final bool stored;

  static TransferReceipt fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var transferId = '';
    var fileId = '';
    var fileName = '';
    var size = 0;
    var sha256Hex = '';
    var stored = false;

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      final field = tag >> 3;
      final wireType = tag & 7;
      switch (field) {
        case 1:
          transferId = reader.readString();
          break;
        case 2:
          fileId = reader.readString();
          break;
        case 3:
          fileName = reader.readString();
          break;
        case 4:
          size = reader.readVarint();
          break;
        case 5:
          sha256Hex = reader.readString();
          break;
        case 6:
          stored = reader.readBool();
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return TransferReceipt(
      transferId: transferId,
      fileId: fileId,
      fileName: fileName,
      size: size,
      sha256Hex: sha256Hex,
      stored: stored,
    );
  }
}
