import 'dart:convert';
import 'dart:typed_data';
import 'package:home/client.dart';

extension Http1Reader on ByteBufferReader {
  String? tryReadLine() {
    for (int i = 0; i < remaining - 1; ++i) {
      if (peekByte(i) == 13 && peekByte(i + 1) == 10) {
        final bytes = tryRead(i); // Up to \r
        skip(2); // Skip \r\n
        return utf8.decode(bytes!);
      }
    }
    // print('Remaining: $remaining null! ');
    return null;
  }

  int peekByte(int offset) => _buffer[position + offset];

  static Http1Request? tryParseHttp1Request(ByteBufferReader reader) {
    final requestLine = reader.tryReadLine();
    if (requestLine == null) return null;

    // print(requestLine);
    final parts = requestLine.split(' ');
    if (parts.length != 3) return null;

    final method = parts[0];
    final path = parts[1];
    final version = parts[2];

    final headers = <String, String>{};
    while (true) {
      final line = reader.tryReadLine();
      if (line == null) return null;
      if (line.isEmpty) break;

      final idx = line.indexOf(':');
      if (idx == -1) return null;

      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      headers[key.toLowerCase()] = value;
    }

    final contentLength = int.tryParse(headers['content-length'] ?? '0') ?? 0;
    Uint8List? body;

    if (contentLength > 0) {
      final payload = reader.tryRead(contentLength);
      if (payload == null) return null;
      body = payload;
    }

    return Http1Request(method, path, version, headers, body);
  } 
}

class ByteBufferReader {
  late Uint8List _buffer;

  /// How many already have been read
  int position = 0;
  int _end = 0;

  // int get offset => position;

  /// How many unread bytes remain
  int get remaining => _end - position;

  /// Entire buffer view (e.g., for debug)
  Uint8List get rawView => _buffer.sublist(position, _end);

  ByteBufferReader([int initialCapacity = 1024]) {
    _buffer = Uint8List(initialCapacity);
  }
  
  void dispose() {
    _buffer = Uint8List(0); // release memory
    position = 0;
    _end = 0;
  }

  void addData(Uint8List data) {
    final incoming = data.length;
    final available = _end - position; // unread data
    final required = available + incoming; // how much total data we need room for

    // Step 1: Check if we have enough space in the current buffer
    if (_buffer.length < required) {
      // Step 2: Grow the buffer
      final newCapacity = (required * 2).clamp(64, 1 << 20); // 3 ~/ 2
      final newBuffer = Uint8List(newCapacity);

      // Step 3: Copy live (unread) data to beginning of new buffer
      newBuffer.setRange(0, available, _buffer.sublist(position, _end));

      // Step 4: Replace old buffer and reset pointers
      _buffer = newBuffer;
      _end = available;
      position = 0;
    } else if (position > 0) {
      // Step 5: Compact the buffer (shift unread data to front)
      _buffer.setRange(0, available, _buffer.sublist(position, _end));
      _end = available;
      position = 0;
    }

    // Step 6: Append incoming data
    _buffer.setRange(_end, _end + incoming, data);
    _end += incoming;
  }

  /// Returns `length` bytes if available, else null 
  Uint8List? tryRead(int length) {
    if (remaining < length) return null;
    final out = Uint8List.view(_buffer.buffer, _buffer.offsetInBytes + position, length);
    position += length;
    return out;
  }

  /// Peek at `length` bytes without consuming
  Uint8List? peek(int length) {
    if (remaining < length) return null;
    return Uint8List.view(_buffer.buffer, _buffer.offsetInBytes + position, length);
  }

  /// Consume `length` bytes
  bool skip(int length) {
    if (remaining < length) return false;
    position += length;
    return true;
  }

  void consumeFrom(BytesBuilder buffer) {
    addData(buffer.takeBytes());
  }

}