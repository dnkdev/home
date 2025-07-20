import 'package:home/home.dart';
import 'package:home/models.dart';
import 'package:home/response.dart';
import 'package:home/log.dart';
import 'package:http2/src/hpack/hpack.dart' show HPackDecoder;
import 'package:http2/transport.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:collection';

part 'stream.dart';
part 'frame.dart';

const int WINDOW_UPDATE_THRESHOLD = 32768;

mixin TimeOutImplemented {
  Timer? _timeoutTimer;
  final Duration idleTimeout = Duration(seconds: 10);
   void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(idleTimeout, _onTimeout);
  }

  void clearTimeout() {
    _timeoutTimer?.cancel(); // <-- cancel timeout
    _timeoutTimer = null;
  }

  void _resetTimeout() {
    _startTimeout();
  }

  void _onTimeout() ;
}

mixin IClientImplemented implements IClient{
  bool _isClosed = false;
  String? _url;
  Method? _method;
  bool _waitingToWrite = false;
  final StreamController<List<int>> _controller = StreamController();
  final Queue<List<int>> _writeQueue = Queue<List<int>>();

  @override
  void cleanUp({bool soft = true}){
    if (_isClosed) {
      print('Cleaned up when isClosed = true');
      return;
    }

    if (soft){ 
      _flush();
    }
    else {
      socket.shutdown(SocketDirection.both);
    }
    socket.close(); 
    _isClosed = true;
    _writeQueue.clear();
    _waitingToWrite = false;
    _controller.close();
  }

  @override
  void add(List<int> data) {
    if (_isClosed) return;
    _writeQueue.add(data);
    if (!_waitingToWrite) _flush();
  }


  void _flush() {
    while (_writeQueue.isNotEmpty) {
      final chunk = _writeQueue.removeFirst();
      final written = socket.write(chunk);
      if (written < chunk.length) {
        _writeQueue.addFirst(chunk.sublist(written)); // ✅ Add remaining bytes back
        _waitingToWrite = true;
        return;
      }
    }
    _waitingToWrite = false;
  }
 
  void reject ({int? code, String? reason, bool soft = false}) {
    if(!soft) {
      cleanUp(soft:false);
      return;
    }
    else {
      Response.badRequest(statusCode: code ?? 400 ,message: reason ?? 'Bad Request').socksend(this);
    }
  }

}

/// ++++++++++++++++++++++++++++++++++++++++++++++++++++++
/// 
/// ++++++++++++++++++ MAIN CLIENT CLASS +++++++++++++++++
/// 
/// ++++++++++++++++++(socket connection)+++++++++++++++++
/// 
/// ++++++++++++++++++++++++++++++++++++++++++++++++++++++
class Client with IClientImplemented, TimeOutImplemented  {
  final RawSecureSocket _socket;

  @override get url => _url;

  @override get method => _method;

  @override RawSecureSocket get socket => _socket;
  
  @override bool get isClosed => _isClosed;

  Client(this._socket);

  State state = State.waitingPreface;

  int _connectionWindowSize = 65535;
  final Map<int, int> _streamWindows = {};
  final Map<int, Http2Stream> _streams = {};
  final _hpackDecoder = HPackDecoder();
  final Map<int, List<Uint8List>> _continuationBuffers = {};

  final buffer = BytesBuilder();
  final reader = ByteBufferReader();

  void handleConnection() {

    socket.listen((event) async {
      if (event == RawSocketEvent.read) {
        _resetTimeout();
        // Read all available bytes
        while (true) {
          final chunk = socket.read();
          if (chunk == null) break;
          buffer.add(chunk);
        }
        // Try to parse as much as possible from buffer
        await parseBuffer();
      } else if (event == RawSocketEvent.closed || event == RawSocketEvent.readClosed) {
        print('Connection closed');
        cleanUp();
      }
    }, onError: (e) {
      print('Socket error: $e');
      cleanUp(soft: false);
    }, onDone: () {
      print('Socket done');
    });
  }

  @override
  void _onTimeout() {
    Log.debug(()=> 'Client Timed out ${socket.remoteAddress.address}:${socket.remotePort}');
    cleanUp(soft: false);
  }


  void _maybeSendWindowUpdate(int streamId) {
    final currentWindow = streamId == 0 ? _connectionWindowSize : _streamWindows[streamId] ?? 0;

    if (currentWindow <= WINDOW_UPDATE_THRESHOLD) {
      final increment = 65535 - currentWindow; // or some other value

      if (increment > 0) {
        _sendWindowUpdate(streamId, increment);
        if (streamId == 0) {
          _connectionWindowSize += increment;
        } else {
          _streamWindows[streamId] = ( _streamWindows[streamId] ?? 0) + increment;
        }
      }
    }
  }

  void _handleFrame(Http2Frame frame) {
    print(frame.type);
    switch (frame.type) {
      case 0x0: _handleDataFrame(frame); break;
      case 0x1: _handleHeadersFrame(frame); break;
      case 0x4: _handleSettingsFrame(frame); break;
      case 0x6: _handlePingFrame(frame); break;
      case 0x8: _handleWindowUpdateFrame(frame); break; // <-- ADD THIS
      case 0x9: _handleContinuationFrame(frame); break;
      default: _sendGoaway(error: 0x1); // PROTOCOL_ERROR
    }
  }

  void _handleWindowUpdateFrame(Http2Frame frame) {
    if (frame.payload.length != 4) {
      _sendGoaway(error: 0x6); // FRAME_SIZE_ERROR
      return;
    }
    final windowSizeIncrement = 
      ((frame.payload[0] & 0x7F) << 24) |
      (frame.payload[1] << 16) |
      (frame.payload[2] << 8) |
      frame.payload[3];

    if (windowSizeIncrement == 0) {
      _sendGoaway(error: 0x1); // PROTOCOL_ERROR
      return;
    }

    final streamId = frame.streamId;

    if (streamId == 0) {
      // Connection-level window update
      // TODO: update connection window size
      print('Received connection-level WINDOW_UPDATE: $windowSizeIncrement');
      _connectionWindowSize += windowSizeIncrement;
      if (_connectionWindowSize > 0x7FFFFFFF) {
        _sendGoaway(error: 0x3); // FLOW_CONTROL_ERROR
        cleanUp(soft: false);
        return;
      }
    } else {
      // Stream-level window update
      final streamWindow = (_streamWindows[streamId] ?? 65535) + windowSizeIncrement;
      
      if (streamWindow > 0x7FFFFFFF) {
        _sendRstStream(streamId, 0x3); // FLOW_CONTROL_ERROR
        return;
      }
      
      _streamWindows[streamId] = streamWindow;
      print('Received WINDOW_UPDATE for stream $streamId: $windowSizeIncrement');
    }
  }

  void _sendRstStream(int streamId, int errorCode) {
    final frameHeader = Uint8List(9);

    // Length: 4 bytes (error code)
    frameHeader[0] = 0;
    frameHeader[1] = 0;
    frameHeader[2] = 4;

    frameHeader[3] = 0x3; // Type = RST_STREAM
    frameHeader[4] = 0x0; // Flags = 0

    // Stream ID (31 bits)
    frameHeader[5] = (streamId >> 24) & 0x7F; // MSB zeroed
    frameHeader[6] = (streamId >> 16) & 0xFF;
    frameHeader[7] = (streamId >> 8) & 0xFF;
    frameHeader[8] = streamId & 0xFF;

    final payload = Uint8List(4);

    // Error code (4 bytes)
    payload[0] = (errorCode >> 24) & 0xFF;
    payload[1] = (errorCode >> 16) & 0xFF;
    payload[2] = (errorCode >> 8) & 0xFF;
    payload[3] = errorCode & 0xFF;

    final frame = BytesBuilder();
    frame.add(frameHeader);
    frame.add(payload);

    add(frame.toBytes());

    print('Sent RST_STREAM for stream $streamId with error $errorCode');
  }

  void _sendWindowUpdate(int streamId, int windowSizeIncrement) {
    final frameHeader = Uint8List(9);

    // Length: 4 bytes (window size increment)
    frameHeader[0] = 0;
    frameHeader[1] = 0;
    frameHeader[2] = 4;

    frameHeader[3] = 0x8; // Type = WINDOW_UPDATE
    frameHeader[4] = 0x0; // Flags = 0

    // Stream ID (31 bits)
    frameHeader[5] = (streamId >> 24) & 0x7F; // MSB zeroed
    frameHeader[6] = (streamId >> 16) & 0xFF;
    frameHeader[7] = (streamId >> 8) & 0xFF;
    frameHeader[8] = streamId & 0xFF;

    final payload = Uint8List(4);

    // Window size increment (31 bits)
    payload[0] = (windowSizeIncrement >> 24) & 0x7F; // MSB zeroed
    payload[1] = (windowSizeIncrement >> 16) & 0xFF;
    payload[2] = (windowSizeIncrement >> 8) & 0xFF;
    payload[3] = windowSizeIncrement & 0xFF;

    final frame = BytesBuilder();
    frame.add(frameHeader);
    frame.add(payload);

    add(frame.toBytes());

    print('Sent WINDOW_UPDATE for stream $streamId with increment $windowSizeIncrement');
  }


  void _sendGoaway({int lastStreamId = 0, int error = 0}) {
    final payload = BytesBuilder();

    // Last Stream ID (31 bits)
    payload.add([
      (lastStreamId >> 24) & 0x7F,  // highest 7 bits (MSB must be zero)
      (lastStreamId >> 16) & 0xFF,
      (lastStreamId >> 8) & 0xFF,
      lastStreamId & 0xFF,
    ]);

    // Error code (4 bytes)
    payload.add([
      (error >> 24) & 0xFF,
      (error >> 16) & 0xFF,
      (error >> 8) & 0xFF,
      error & 0xFF,
    ]);

    final framePayload = payload.toBytes();

    final frameHeader = Uint8List(9);

    // Length: 8 bytes (lastStreamId + error)
    frameHeader[0] = 0;
    frameHeader[1] = 0;
    frameHeader[2] = 8;

    frameHeader[3] = 0x7; // Type = GOAWAY
    frameHeader[4] = 0x0; // Flags = 0
    frameHeader[5] = 0x0; // Stream ID = 0
    frameHeader[6] = 0x0;
    frameHeader[7] = 0x0;
    frameHeader[8] = 0x0;

    final frame = BytesBuilder();
    frame.add(frameHeader);
    frame.add(framePayload);

    add(frame.toBytes());

    print('Sent GOAWAY with error $error and lastStreamId $lastStreamId');
  }


  void _handlePingFrame(Http2Frame frame) {
    if (frame.payload.length != 8) {
      _sendGoaway(error: 0x2); // FRAME_SIZE_ERROR
      return;
    }

    final isAck = (frame.flags & 0x1) != 0;
    if (isAck) {
      print('Received PING ACK');
      return;
    }

    final response = BytesBuilder();
    response.add([0, 0, 8]); // length = 8
    response.add([0x6]);     // type = PING
    response.add([0x1]);     // ACK flag
    response.add([0, 0, 0, 0]); // streamId = 0
    response.add(frame.payload); // echo back

    add(response.toBytes());
  }

  void _handleSettingsFrame(Http2Frame frame) {
    final isAck = (frame.flags & 0x1) != 0;

    if (isAck) {
      print('Received SETTINGS ACK');
      return;
    }

    // Accept all settings silently for now
    print('Received SETTINGS, sending ACK');

    final ack = Uint8List(9); // empty payload, type = 0x4, flags = 0x1
    ack[3] = 0x4; // type = SETTINGS
    ack[4] = 0x1; // ACK flag
    // ack[5..8] = streamId = 0 (already zero)

    add(ack);
  }

  void _handleDataFrame(Http2Frame frame) {
    final stream = _streams[frame.streamId];
    if (stream == null) {
      _sendGoaway(error: 0x1); // PROTOCOL_ERROR
      return;
    }

    final dataLength = frame.length;
    if (_connectionWindowSize < dataLength) {
      _sendGoaway(error: 0x3); // FLOW_CONTROL_ERROR
      cleanUp(soft: false);
      return;
    }
    if (!_streamWindows.containsKey(frame.streamId) || _streamWindows[frame.streamId]! < dataLength) {
      _sendRstStream(frame.streamId, 0x3); // FLOW_CONTROL_ERROR
      return;
    }

    _connectionWindowSize -= dataLength;
    _streamWindows[frame.streamId] = _streamWindows[frame.streamId]! - dataLength;

    stream.addDataFragment(frame.payload);

    final isEndStream = (frame.flags & 0x1) != 0;
    if (isEndStream) {
      stream.closeRemote();
    }
  }

  // void _parseFrame(Uint8List frame) {
  //   final parsed = Http2Frame.tryParse(frame);
  //   if (parsed == null) return ;
  //   _handleFrame(parsed);
  // }




  void _processFrames() {
    while (true) {
      final peeked = reader.peek(Http2Frame.headerSize);
      if (peeked == null) return;

      final totalSize = Http2Frame.getTotalFrameSize(peeked);
      if (reader.remaining < totalSize) return;

      final raw = reader.tryRead(totalSize)!;
      final frame = Http2Frame.tryParse(raw);
      if (frame != null) {
        _handleFrame(frame);
      } else {
        _sendGoaway(error: 0x1); // PROTOCOL_ERROR
        return;
      }
    }
  }
  
  void _handleContinuationFrame(Http2Frame frame) {
  final streamId = frame.streamId;

  final buffer = _continuationBuffers[streamId];
  if (buffer == null) {
    // CONTINUATION frame received without prior HEADERS/CONTINUATION frames
    _sendGoaway(error: 0x1); // Protocol error
    return;
  }

  buffer.add(frame.payload);

  final isEndHeaders = (frame.flags & 0x4) != 0;
  if (isEndHeaders) {
    final stream = _streams[streamId];
    if (stream == null) {
      _sendGoaway(error: 0x1);
      return;
    }

    final fullBlock = _mergeContinuations(streamId);
    stream.decodedHeaders = _hpackDecoder.decode(fullBlock);
    _continuationBuffers.remove(streamId);
  }
}

  Uint8List _mergeContinuations(int streamId) {
    final parts = _continuationBuffers[streamId]!;
    final builder = BytesBuilder(copy: false);
    for (final chunk in parts) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  void _handleHeadersFrame(Http2Frame frame) {
  final streamId = frame.streamId;
  final stream = _streams.putIfAbsent(streamId, () => Http2Stream(streamId));

  final isEndHeaders = (frame.flags & 0x4) != 0;
  final isEndStream = (frame.flags & 0x1) != 0;

  if (_continuationBuffers.containsKey(streamId)) {
    // Unexpected new HEADERS frame before previous CONTINUATION finished
    _sendGoaway(error: 0x1); // Protocol error
    return;
  }

  // Initialize continuation buffer with the HEADERS payload
  _continuationBuffers[streamId] = [frame.payload];
  _streamWindows.putIfAbsent(streamId, () => 65535);
  if (isEndHeaders) {
    // No CONTINUATION frames expected, decode immediately
    final fullBlock = _mergeContinuations(streamId);
    stream.decodedHeaders = _hpackDecoder.decode(fullBlock);
    _continuationBuffers.remove(streamId);
  }

  if (stream.state == Http2StreamState.idle) {
    stream.state = Http2StreamState.open;
  }
  if (isEndStream) {
    stream.closeRemote();
  }
}

  String? parsePreface() {
    reader.addData(buffer.toBytes()); // consume BytesBuilder
    buffer.clear();
    final prefaceBytes = reader.tryRead(24);
    if (prefaceBytes == null) return null; // not enough data
    print('prefaceBytes ${prefaceBytes.length}');
    return utf8.decode(prefaceBytes);
  }

  Future<void> parseBuffer() async {
    switch (state){
      case State.waitingPreface:
        if (buffer.length >= 24) {
          final preface = parsePreface();
          if (preface == http2Preface) {
            print('Preface matches!!');
            state = State.readingFrames;
          }
        }
        break;
      case State.readingFrames:
        print('will be handling frames');
        _processFrames();  // _processFrames will handle reading the frames properly
        break;
    }
  }

  @override
  void cleanUp({soft = true}) {
   if (_isClosed) {
      print('Cleaned up when isClosed = true');
      return;
    }

    _timeoutTimer?.cancel(); // <-- cancel timeout
    _timeoutTimer = null;
    if (soft){ 
      _flush();
    }
    else {
      socket.shutdown(SocketDirection.both);
    }
    socket.close(); 
    _isClosed = true;
    _writeQueue.clear();
    _waitingToWrite = false;
    _controller.close(); 

  }

}

const http2Preface = 'PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n';

enum State { 
  waitingPreface, 
  readingFrames 
}

