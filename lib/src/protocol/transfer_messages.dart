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

  static HandshakeRequest fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var clientDeviceId = '';
    var clientName = '';
    var clientPublicKey = <int>[];
    final supportedCiphers = <String>[];

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      final field = tag >> 3;
      final wireType = tag & 7;
      switch (field) {
        case 1:
          clientDeviceId = reader.readString();
          break;
        case 2:
          clientName = reader.readString();
          break;
        case 3:
          clientPublicKey = reader.readLengthDelimited();
          break;
        case 4:
          supportedCiphers.add(reader.readString());
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return HandshakeRequest(
      clientDeviceId: clientDeviceId,
      clientName: clientName,
      clientPublicKey: clientPublicKey,
      supportedCiphers: List<String>.unmodifiable(supportedCiphers),
    );
  }

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

  List<int> writeToBuffer() {
    return (ProtoWriter()
          ..writeString(1, sessionId)
          ..writeString(2, serverDeviceId)
          ..writeString(3, serverName)
          ..writeBytes(4, serverPublicKey)
          ..writeString(5, selectedCipher)
          ..writeUint64(6, expiresAtUnixTimeMs))
        .takeBytes();
  }

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

  static FileChunk fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var sessionId = '';
    var transferId = '';
    var fileName = '';
    var totalSize = 0;
    var offset = 0;
    var nonce = <int>[];
    var data = <int>[];
    var authTag = <int>[];
    var encrypted = false;
    var sha256Hex = '';

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      final field = tag >> 3;
      final wireType = tag & 7;
      switch (field) {
        case 1:
          sessionId = reader.readString();
          break;
        case 2:
          transferId = reader.readString();
          break;
        case 3:
          fileName = reader.readString();
          break;
        case 4:
          totalSize = reader.readVarint();
          break;
        case 5:
          offset = reader.readVarint();
          break;
        case 6:
          nonce = reader.readLengthDelimited();
          break;
        case 7:
          data = reader.readLengthDelimited();
          break;
        case 8:
          authTag = reader.readLengthDelimited();
          break;
        case 9:
          encrypted = reader.readBool();
          break;
        case 10:
          sha256Hex = reader.readString();
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return FileChunk(
      sessionId: sessionId,
      transferId: transferId,
      fileName: fileName,
      totalSize: totalSize,
      offset: offset,
      nonce: nonce,
      data: data,
      authTag: authTag,
      encrypted: encrypted,
      sha256Hex: sha256Hex,
    );
  }

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

class ListFilesRequest {
  const ListFilesRequest({
    required this.sessionId,
  });

  final String sessionId;

  static ListFilesRequest fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var sessionId = '';
    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      final field = tag >> 3;
      final wireType = tag & 7;
      switch (field) {
        case 1:
          sessionId = reader.readString();
          break;
        default:
          reader.skipField(wireType);
      }
    }
    return ListFilesRequest(sessionId: sessionId);
  }

  List<int> writeToBuffer() {
    return (ProtoWriter()..writeString(1, sessionId)).takeBytes();
  }
}

class EventSubscription {
  const EventSubscription({
    required this.sessionId,
    required this.clientDeviceId,
    required this.clientName,
    required this.eventTypes,
  });

  final String sessionId;
  final String clientDeviceId;
  final String clientName;
  final List<String> eventTypes;

  static EventSubscription fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var sessionId = '';
    var clientDeviceId = '';
    var clientName = '';
    final eventTypes = <String>[];

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      final field = tag >> 3;
      final wireType = tag & 7;
      switch (field) {
        case 1:
          sessionId = reader.readString();
          break;
        case 2:
          clientDeviceId = reader.readString();
          break;
        case 3:
          clientName = reader.readString();
          break;
        case 4:
          eventTypes.add(reader.readString());
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return EventSubscription(
      sessionId: sessionId,
      clientDeviceId: clientDeviceId,
      clientName: clientName,
      eventTypes: List<String>.unmodifiable(eventTypes),
    );
  }

  List<int> writeToBuffer() {
    final writer = ProtoWriter()
      ..writeString(1, sessionId)
      ..writeString(2, clientDeviceId)
      ..writeString(3, clientName);
    for (final eventType in eventTypes) {
      writer.writeString(4, eventType);
    }
    return writer.takeBytes();
  }
}

class ServerEvent {
  const ServerEvent({
    required this.eventId,
    required this.type,
    required this.unixTimeMs,
    required this.message,
    required this.sessionId,
    required this.peerDeviceId,
    required this.peerName,
    required this.file,
  });

  final String eventId;
  final String type;
  final int unixTimeMs;
  final String message;
  final String sessionId;
  final String peerDeviceId;
  final String peerName;
  final FileEntry? file;

  List<int> writeToBuffer() {
    final writer = ProtoWriter()
      ..writeString(1, eventId)
      ..writeString(2, type)
      ..writeUint64(3, unixTimeMs)
      ..writeString(4, message)
      ..writeString(5, sessionId)
      ..writeString(6, peerDeviceId)
      ..writeString(7, peerName);
    final currentFile = file;
    if (currentFile != null) {
      writer.writeBytes(8, currentFile.writeToBuffer());
    }
    return writer.takeBytes();
  }

  static ServerEvent fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var eventId = '';
    var type = '';
    var unixTimeMs = 0;
    var message = '';
    var sessionId = '';
    var peerDeviceId = '';
    var peerName = '';
    FileEntry? file;

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      final field = tag >> 3;
      final wireType = tag & 7;
      switch (field) {
        case 1:
          eventId = reader.readString();
          break;
        case 2:
          type = reader.readString();
          break;
        case 3:
          unixTimeMs = reader.readVarint();
          break;
        case 4:
          message = reader.readString();
          break;
        case 5:
          sessionId = reader.readString();
          break;
        case 6:
          peerDeviceId = reader.readString();
          break;
        case 7:
          peerName = reader.readString();
          break;
        case 8:
          file = FileEntry.fromBuffer(reader.readLengthDelimited());
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return ServerEvent(
      eventId: eventId,
      type: type,
      unixTimeMs: unixTimeMs,
      message: message,
      sessionId: sessionId,
      peerDeviceId: peerDeviceId,
      peerName: peerName,
      file: file,
    );
  }
}

class FileEntry {
  const FileEntry({
    required this.fileId,
    required this.fileName,
    required this.size,
    required this.sha256Hex,
    required this.receivedAtUnixTimeMs,
  });

  final String fileId;
  final String fileName;
  final int size;
  final String sha256Hex;
  final int receivedAtUnixTimeMs;

  List<int> writeToBuffer() {
    return (ProtoWriter()
          ..writeString(1, fileId)
          ..writeString(2, fileName)
          ..writeUint64(3, size)
          ..writeString(4, sha256Hex)
          ..writeUint64(5, receivedAtUnixTimeMs))
        .takeBytes();
  }

  static FileEntry fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var fileId = '';
    var fileName = '';
    var size = 0;
    var sha256Hex = '';
    var receivedAtUnixTimeMs = 0;

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      final field = tag >> 3;
      final wireType = tag & 7;
      switch (field) {
        case 1:
          fileId = reader.readString();
          break;
        case 2:
          fileName = reader.readString();
          break;
        case 3:
          size = reader.readVarint();
          break;
        case 4:
          sha256Hex = reader.readString();
          break;
        case 5:
          receivedAtUnixTimeMs = reader.readVarint();
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return FileEntry(
      fileId: fileId,
      fileName: fileName,
      size: size,
      sha256Hex: sha256Hex,
      receivedAtUnixTimeMs: receivedAtUnixTimeMs,
    );
  }
}

class ListFilesResponse {
  const ListFilesResponse({
    required this.files,
  });

  final List<FileEntry> files;

  List<int> writeToBuffer() {
    final writer = ProtoWriter();
    for (final file in files) {
      writer.writeBytes(1, file.writeToBuffer());
    }
    return writer.takeBytes();
  }

  static ListFilesResponse fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    final files = <FileEntry>[];

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      final field = tag >> 3;
      final wireType = tag & 7;
      switch (field) {
        case 1:
          files.add(FileEntry.fromBuffer(reader.readLengthDelimited()));
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return ListFilesResponse(files: List<FileEntry>.unmodifiable(files));
  }
}

class FileRequest {
  const FileRequest({
    required this.sessionId,
    required this.fileId,
  });

  final String sessionId;
  final String fileId;

  List<int> writeToBuffer() {
    return (ProtoWriter()
          ..writeString(1, sessionId)
          ..writeString(2, fileId))
        .takeBytes();
  }

  static FileRequest fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var sessionId = '';
    var fileId = '';

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      final field = tag >> 3;
      final wireType = tag & 7;
      switch (field) {
        case 1:
          sessionId = reader.readString();
          break;
        case 2:
          fileId = reader.readString();
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return FileRequest(
      sessionId: sessionId,
      fileId: fileId,
    );
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

  List<int> writeToBuffer() {
    return (ProtoWriter()
          ..writeString(1, transferId)
          ..writeString(2, fileId)
          ..writeString(3, fileName)
          ..writeUint64(4, size)
          ..writeString(5, sha256Hex)
          ..writeBool(6, stored))
        .takeBytes();
  }

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
