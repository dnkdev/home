/// parseBuffer should allow HTTP pipelining ( multiple requests in one connection ), 
/// but right now it is not completely used in this server (as well in browsers), so it is in TODO
library;

import 'package:home/response.dart';
import 'package:home/log.dart';
import 'package:home/bytebuffer.dart';
import 'package:home/router.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'dart:collection';

part 'http1.dart';

// const http2Preface = 'PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n';
const maxHttp1PipelinedReuquests = 8;

enum State { 
  readingHttp1,
  waitingPreface, 
  readingFrames 
}


mixin TimeOutImplemented {
  Timer? _timeoutTimer;
  final Duration idleTimeout = Duration(seconds: 10);
   void startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(idleTimeout, onTimeout);
  }

  void clearTimeout() {
    _timeoutTimer?.cancel(); // <-- cancel timeout
    _timeoutTimer = null;
  }

  void resetTimeout() {
    startTimeout();
  }

  void onTimeout() ;

}


/// ++++++++++++++++++++++++++++++++++++++++++++++++++++++
/// 
/// ++++++++++++++++++ MAIN CLIENT CLASS +++++++++++++++++
/// 
/// ++++++++++++++++++(socket connection)+++++++++++++++++
/// 
/// ++++++++++++++++++++++++++++++++++++++++++++++++++++++
class Client with TimeOutImplemented  {
  bool _isClosed = false;
  bool _waitingToWrite = false;
  final StreamController<List<int>> _controller = StreamController();
  final Queue<List<int>> _writeQueue = Queue<List<int>>();
  final RawSecureSocket _socket;
  final String ip;
  final int remotePort;
  Http1Request? request;

  RawSecureSocket get socket => _socket;

  bool get isClosed => _isClosed;

  Client(this._socket, this.ip, this.remotePort);

  State state = State.readingHttp1;

  final buffer = BytesBuilder();
  final reader = ByteBufferReader();

  void reject ({int? code, String? reason, bool soft = false}) {
    if(!soft) {
      cleanUp(soft:false);
      return;
    }
    else {
      Response.badRequest(statusCode: code ?? 400 ,message: reason ?? 'Bad Request').socksend(this);
    }
  }

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

  void handleConnection() {

    resetTimeout();
    socket.listen((event) async {
      switch(event) {
        case RawSocketEvent.read:
          // Read all available bytes
          while (true) {
            final chunk = socket.read();
            if (chunk == null) break;
            buffer.add(chunk);
          }
          // Try to parse as much as possible from buffer
          await parseBuffer(pipelineRequest: false);
        break;
        case RawSocketEvent.write:
          _flush();
        break;
        case RawSocketEvent.readClosed:
        case RawSocketEvent.closed:
          Log.debug(()=>'[$ip:$remotePort] Client connection closed');
          cleanUp();
        break;
        
      }
    }, onError: (e) {
      Log.error(()=>'[$ip:$remotePort] Socket error: $e');
      cleanUp(soft: false);
    }, onDone: () {
      Log.debug(()=>'[$ip:$remotePort] Socket done');
    });
  }

  Future<void> _respond(Http1Request request) async {
    Log.debug(() => '[$ip:$remotePort] ${request.path} ${request.method}');

    await request.waitForBody(); // ✅ Wait for full body

    final route = Router.get(request.path);
    if (route != null) {
      route.clientHandler(this);
    } else {
      Response.notFound().socksend(this);
    }
  }

  Future<void> parseBuffer({bool pipelineRequest = true, int pipeCount = 0}) async {
    switch (state) {
      case State.readingHttp1: {
        reader.consumeFrom(buffer);
        buffer.clear();

        final request = Http1Reader.tryParseHttp1Request(reader);
        if (request == null) return;

        if (request.hasBody) {
          final cl = request.contentLength;

          if (reader.remaining < cl) {
            // Not enough body yet — restore unread header & return
            buffer.add(reader.takeRemaining());
            return;
          }

          request.body = reader.take(cl);
          request.bodyComplete.complete();
        } else {
          request.bodyComplete.complete();
        }

        await _respond(request);

        // Pipelined request support
        if (pipelineRequest &&
            pipeCount < maxHttp1PipelinedReuquests &&
            reader.remaining > 0) {
          await parseBuffer(pipelineRequest: true, pipeCount: pipeCount + 1);
        }

        break;
      }

      case State.waitingPreface:
      case State.readingFrames:
        break;
    }
  }

  @override
  void onTimeout() {
    Log.debug(()=> '[$ip:$remotePort] Client Timed out');
    cleanUp(soft: false);
  }

  void cleanUp({bool soft = true}) {
   if (_isClosed) {
      Log.debug(()=>'[$ip:$remotePort] Cleaned up when isClosed = true');
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
