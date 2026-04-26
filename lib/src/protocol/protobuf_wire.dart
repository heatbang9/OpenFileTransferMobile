import 'dart:convert';

class ProtoWriter {
  final List<int> _bytes = <int>[];

  List<int> takeBytes() => List<int>.unmodifiable(_bytes);

  void writeString(int fieldNumber, String value) {
    if (value.isEmpty) {
      return;
    }
    writeBytes(fieldNumber, utf8.encode(value));
  }

  void writeBytes(int fieldNumber, List<int> value) {
    if (value.isEmpty) {
      return;
    }
    _writeVarint((fieldNumber << 3) | 2);
    _writeVarint(value.length);
    _bytes.addAll(value);
  }

  void writeUint64(int fieldNumber, int value) {
    _writeVarint(fieldNumber << 3);
    _writeVarint(value);
  }

  void writeBool(int fieldNumber, bool value) {
    _writeVarint(fieldNumber << 3);
    _writeVarint(value ? 1 : 0);
  }

  void _writeVarint(int value) {
    var current = value;
    while (current > 0x7f) {
      _bytes.add((current & 0x7f) | 0x80);
      current >>= 7;
    }
    _bytes.add(current);
  }
}

class ProtoReader {
  ProtoReader(List<int> bytes) : _bytes = bytes;

  final List<int> _bytes;
  int _offset = 0;

  bool get isAtEnd => _offset >= _bytes.length;

  int readTag() => readVarint();

  int readVarint() {
    var shift = 0;
    var result = 0;
    while (true) {
      if (_offset >= _bytes.length) {
        throw const FormatException('protobuf varint가 중간에 끝났습니다.');
      }
      final byte = _bytes[_offset++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return result;
      }
      shift += 7;
      if (shift > 63) {
        throw const FormatException('protobuf varint가 너무 깁니다.');
      }
    }
  }

  List<int> readLengthDelimited() {
    final length = readVarint();
    final end = _offset + length;
    if (end > _bytes.length) {
      throw const FormatException('protobuf length-delimited 값이 중간에 끝났습니다.');
    }
    final value = _bytes.sublist(_offset, end);
    _offset = end;
    return value;
  }

  String readString() => utf8.decode(readLengthDelimited());

  bool readBool() => readVarint() != 0;

  void skipField(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
        break;
      case 2:
        readLengthDelimited();
        break;
      default:
        throw FormatException('지원하지 않는 protobuf wire type: $wireType');
    }
  }
}
