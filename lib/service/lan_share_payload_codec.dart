class LanSharePayloadCodec {
  static const String base62Alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  static const int _base62 = 62;
  static const int _payloadVersion = 0;
  static const int _private192168Span = 1 << 16;
  static const int _private172Span = 16 << 16;
  static const int _private10Span = 1 << 24;
  static const int _private172Offset = _private192168Span;
  static const int _private10Offset = _private172Offset + _private172Span;
  static const int _privateTotalSpan = _private10Offset + _private10Span;
  static const int _firstIdBitWidth = 25;

  static final Map<int, int> _base62DecodeMap = <int, int>{
    for (var index = 0; index < base62Alphabet.length; index++)
      base62Alphabet.codeUnitAt(index): index,
  };

  static String encodeCompactRoute({
    required String shareKey,
    required List<String> lanIps,
  }) {
    final normalizedShareKey = shareKey.trim();
    if (normalizedShareKey.isEmpty) {
      throw ArgumentError.value(
        shareKey,
        'shareKey',
        'shareKey cannot be empty.',
      );
    }
    if (!_isBase62(normalizedShareKey)) {
      throw ArgumentError.value(
        shareKey,
        'shareKey',
        'shareKey must use Base62 characters only.',
      );
    }
    if (normalizedShareKey.length > base62Alphabet.length) {
      throw ArgumentError.value(
        shareKey,
        'shareKey',
        'shareKey is too long to encode in a single length marker.',
      );
    }

    final routePayload = _encodeIpv4ListPayload(lanIps);
    final shareKeyLengthMarker = base62Alphabet[normalizedShareKey.length - 1];
    return '$shareKeyLengthMarker$normalizedShareKey$routePayload';
  }

  static Map<String, dynamic> decodeCompactRoute(String payload) {
    final normalized = Uri.decodeComponent(payload.trim());
    if (normalized.isEmpty) {
      throw const FormatException('Compact route payload cannot be empty.');
    }
    if (!_isBase62(normalized)) {
      throw const FormatException(
        'Compact route payload must use Base62 characters only.',
      );
    }

    final shareKeyLengthMarker = normalized.codeUnitAt(0);
    final shareKeyLengthDigit = _base62DecodeMap[shareKeyLengthMarker];
    if (shareKeyLengthDigit == null) {
      throw const FormatException('Compact route shareKey length is invalid.');
    }
    final shareKeyLength = shareKeyLengthDigit + 1;
    if (normalized.length <= shareKeyLength) {
      throw const FormatException(
        'Compact route payload is truncated before route payload begins.',
      );
    }

    final shareKey = normalized.substring(1, 1 + shareKeyLength);
    if (!_isBase62(shareKey)) {
      throw const FormatException(
        'Compact route shareKey must be a non-empty Base62 string.',
      );
    }

    final routePayload = normalized.substring(1 + shareKeyLength);
    final lanIps = _decodeIpv4ListPayload(routePayload);
    return <String, dynamic>{'shareKey': shareKey, 'lanIps': lanIps};
  }

  static String encodeBase62(int value) {
    if (value < 0) {
      throw ArgumentError.value(
        value,
        'value',
        'Base62 value cannot be negative.',
      );
    }
    if (value == 0) {
      return base62Alphabet[0];
    }

    final chars = <String>[];
    var remaining = value;
    while (remaining > 0) {
      final digit = remaining % _base62;
      chars.add(base62Alphabet[digit]);
      remaining ~/= _base62;
    }
    return chars.reversed.join();
  }

  static String _encodeIpv4ListPayload(List<String> lanIps) {
    final ids =
        lanIps.map(_mapRfc1918Ipv4ToOrdinal).toSet().toList(growable: false)
          ..sort();
    if (ids.isEmpty) {
      throw ArgumentError.value(
        lanIps,
        'lanIps',
        'At least one RFC1918 IPv4 address is required.',
      );
    }

    final bits = StringBuffer();
    _writeUleb128Bits(bits, _payloadVersion);
    _writeUleb128Bits(bits, ids.length);
    _writeFixedWidthBits(bits, ids.first, _firstIdBitWidth);
    for (var index = 1; index < ids.length; index += 1) {
      _writeUleb128Bits(bits, ids[index] - ids[index - 1]);
    }

    final payloadBits = '1${bits.toString()}';
    final value = BigInt.parse(payloadBits, radix: 2);
    return encodeBase62BigInt(value);
  }

  static List<String> _decodeIpv4ListPayload(String payload) {
    if (payload.isEmpty || !_isBase62(payload)) {
      throw const FormatException(
        'Compact route IPv4 payload must be a non-empty Base62 string.',
      );
    }

    final value = _decodeBase62BigInt(payload);
    final binary = value.toRadixString(2);
    if (binary.isEmpty || binary[0] != '1') {
      throw const FormatException(
        'Compact route IPv4 payload is missing sentinel bit.',
      );
    }

    final reader = _BitReader(binary.substring(1));
    final version = _readUleb128Bits(reader);
    if (version != _payloadVersion) {
      throw FormatException('Unsupported compact route version: $version');
    }

    final count = _readUleb128Bits(reader);
    if (count <= 0) {
      throw const FormatException(
        'Compact route must contain at least one LAN IP.',
      );
    }

    final ids = <int>[];
    final firstId = _readFixedWidthBits(reader, _firstIdBitWidth);
    ids.add(firstId);
    for (var index = 1; index < count; index += 1) {
      final delta = _readUleb128Bits(reader);
      ids.add(ids.last + delta);
    }

    if (!reader.isAtEnd) {
      throw const FormatException(
        'Compact route IPv4 payload contains unexpected trailing bits.',
      );
    }

    return ids.map(_mapOrdinalToRfc1918Ipv4).toList(growable: false);
  }

  static String encodeBase62BigInt(BigInt value) {
    if (value < BigInt.zero) {
      throw ArgumentError.value(
        value,
        'value',
        'Base62 BigInt value cannot be negative.',
      );
    }
    if (value == BigInt.zero) {
      return base62Alphabet[0];
    }

    final chars = <String>[];
    final radix = BigInt.from(_base62);
    var remaining = value;
    while (remaining > BigInt.zero) {
      final digit = (remaining % radix).toInt();
      chars.add(base62Alphabet[digit]);
      remaining ~/= radix;
    }
    return chars.reversed.join();
  }

  static BigInt _decodeBase62BigInt(String encoded) {
    var value = BigInt.zero;
    final radix = BigInt.from(_base62);
    for (final codeUnit in encoded.codeUnits) {
      final digit = _base62DecodeMap[codeUnit];
      if (digit == null) {
        throw FormatException(
          'Invalid Base62 character: ${String.fromCharCode(codeUnit)}',
        );
      }
      value = value * radix + BigInt.from(digit);
    }
    return value;
  }

  static int _mapRfc1918Ipv4ToOrdinal(String ip) {
    final segments = _parseIpv4Segments(ip);
    final first = segments[0];
    final second = segments[1];
    final third = segments[2];
    final fourth = segments[3];

    if (first == 192 && second == 168) {
      return (third << 8) | fourth;
    }
    if (first == 172 && second >= 16 && second <= 31) {
      return _private172Offset + ((second - 16) << 16) + (third << 8) + fourth;
    }
    if (first == 10) {
      return _private10Offset + (second << 16) + (third << 8) + fourth;
    }

    throw FormatException(
      'IPv4 address is not inside RFC1918 private space: $ip',
    );
  }

  static String _mapOrdinalToRfc1918Ipv4(int ordinal) {
    if (ordinal < 0 || ordinal >= _privateTotalSpan) {
      throw FormatException(
        'Compact IPv4 ordinal is outside RFC1918 private space: $ordinal',
      );
    }

    if (ordinal < _private172Offset) {
      return '192.168.${(ordinal >> 8) & 0xff}.${ordinal & 0xff}';
    }

    if (ordinal < _private10Offset) {
      final value = ordinal - _private172Offset;
      return '172.${16 + ((value >> 16) & 0x0f)}.${(value >> 8) & 0xff}.${value & 0xff}';
    }

    final value = ordinal - _private10Offset;
    return '10.${(value >> 16) & 0xff}.${(value >> 8) & 0xff}.${value & 0xff}';
  }

  static List<int> _parseIpv4Segments(String ip) {
    final segments = ip.split('.');
    if (segments.length != 4) {
      throw FormatException('Invalid IPv4 address: $ip');
    }
    return segments
        .map((segment) {
          final value = int.tryParse(segment);
          if (value == null || value < 0 || value > 255) {
            throw FormatException('Invalid IPv4 address: $ip');
          }
          return value;
        })
        .toList(growable: false);
  }

  static void _writeUleb128Bits(StringBuffer bits, int value) {
    if (value < 0) {
      throw ArgumentError.value(
        value,
        'value',
        'ULEB128 value cannot be negative.',
      );
    }

    var remaining = value;
    while (true) {
      var byte = remaining & 0x7f;
      remaining >>= 7;
      if (remaining != 0) {
        byte |= 0x80;
      }
      _writeFixedWidthBits(bits, byte, 8);
      if (remaining == 0) {
        return;
      }
    }
  }

  static int _readUleb128Bits(_BitReader reader) {
    var value = 0;
    var shift = 0;
    while (true) {
      final byte = _readFixedWidthBits(reader, 8);
      value |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return value;
      }
      shift += 7;
      if (shift > 63) {
        throw const FormatException('ULEB128 value is too large.');
      }
    }
  }

  static void _writeFixedWidthBits(StringBuffer bits, int value, int width) {
    if (width <= 0) {
      throw ArgumentError.value(width, 'width', 'width must be positive.');
    }
    for (var index = width - 1; index >= 0; index -= 1) {
      bits.write(((value >> index) & 1) == 1 ? '1' : '0');
    }
  }

  static int _readFixedWidthBits(_BitReader reader, int width) {
    if (reader.remaining < width) {
      throw const FormatException('Bitstream ended unexpectedly.');
    }
    var value = 0;
    for (var index = 0; index < width; index += 1) {
      value = (value << 1) | reader.readBit();
    }
    return value;
  }

  static bool _isBase62(String value) {
    if (value.isEmpty) {
      return false;
    }
    for (final codeUnit in value.codeUnits) {
      if (!_base62DecodeMap.containsKey(codeUnit)) {
        return false;
      }
    }
    return true;
  }
}

class _BitReader {
  _BitReader(this._bits);

  final String _bits;
  int _offset = 0;

  int get remaining => _bits.length - _offset;
  bool get isAtEnd => _offset >= _bits.length;

  int readBit() {
    if (_offset >= _bits.length) {
      throw const FormatException('Bitstream ended unexpectedly.');
    }
    final bit = _bits.codeUnitAt(_offset);
    _offset += 1;
    if (bit == 48) {
      return 0;
    }
    if (bit == 49) {
      return 1;
    }
    throw const FormatException('Bitstream contains a non-binary character.');
  }
}
