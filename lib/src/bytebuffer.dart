part of 'home_base.dart';

class ByteBufferReader {
  late Uint8List _buffer;
  int _start = 0;
  int _end = 0;

  ByteBufferReader([int initialCapacity = 1024]) {
    _buffer = Uint8List(initialCapacity);
  }

  /// Adds new data to the buffer
  void addData(Uint8List data) {
    final incoming = data.length;
    final available = _end - _start;
    final required = available + incoming;

    if (_buffer.length < required) {
      // Allocate larger buffer
      final newCapacity = (_buffer.length * 2).clamp(64, 1 << 20);
      final newBuffer = Uint8List(required > newCapacity ? required : newCapacity);
      newBuffer.setRange(0, available, _buffer.sublist(_start, _end));
      _buffer = newBuffer;
      _end = available;
      _start = 0;
    } else if (_start > 0) {
      // Compact by shifting live data to front
      _buffer.setRange(0, available, _buffer.sublist(_start, _end));
      _end = available;
      _start = 0;
    }

    _buffer.setRange(_end, _end + incoming, data);
    _end += incoming;
  }

  /// Returns `length` bytes if available, else null (non-blocking)
  Uint8List? tryRead(int length) {
    if (remaining < length) return null;
    final out = Uint8List.view(_buffer.buffer, _buffer.offsetInBytes + _start, length);
    _start += length;
    return out;
  }

  /// Peek at `length` bytes without consuming
  Uint8List? peek(int length) {
    if (remaining < length) return null;
    return Uint8List.view(_buffer.buffer, _buffer.offsetInBytes + _start, length);
  }

  /// Consume `length` bytes
  bool skip(int length) {
    if (remaining < length) return false;
    _start += length;
    return true;
  }

  void consumeFrom(BytesBuilder buffer) {
    if (this.offset > 0) {
      
    }
  }
  
  void dispose() {
    _buffer = Uint8List(0); // release memory
    _start = 0;
    _end = 0;
  }

  /// How many bytes have been read
  int get offset => _start;

  /// How many unread bytes remain
  int get remaining => _end - _start;


  /// Entire buffer view (e.g., for debug)
  Uint8List get rawView => _buffer.sublist(_start, _end);
}