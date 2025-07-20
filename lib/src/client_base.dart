part of 'home_base.dart';

class Client implements IClient {
  @override
  Method? method;
  @override
  String? url;

  final RawSecureSocket _socket;
  final String ip;
  final int remotePort;
  final StreamController<List<int>> _controller = StreamController();
  final Queue<List<int>> _writeQueue = Queue<List<int>>();
  bool _waitingToWrite = false;
  bool _isClosed = false;

  Client(this._socket) : ip = _socket.remoteAddress.address, remotePort = _socket.remotePort;

  @override
  RawSecureSocket get socket => _socket;


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

  void _reject ({int? code, String? reason, bool soft = false}) {
    if(!soft) {
      cleanUp(soft:false);
      return;
    }
    else {
      Response.badRequest(statusCode: code ?? 400 ,message: reason ?? 'Bad Request').socksend(this);
    }
  }
  void handleSocket() {
    print('Secure connection from ${socket.remoteAddress.address}:${socket.remotePort}');
    final buffer = BytesBuilder();

    socket.listen((event) {
      switch (event) {
        case RawSocketEvent.read:
          final data = socket.read();
          if (data != null) buffer.add(data);

          final text = utf8.decode(buffer.toBytes(), allowMalformed: true);
          if (text.contains('\r\n\r\n')) {
            print('Received:\n$text');

            // Simple HTTP response
            const response = 'HTTP/1.1 200 OK\r\n'
                'Content-Type: text/plain\r\n'
                'Content-Length: 2\r\n'
                '\r\n'
                'OK';

            socket.write(utf8.encode(response));
            socket.close();
          }
          break;

        case RawSocketEvent.write:
          _flush(); // Try to resume writing
          break;

        case RawSocketEvent.readClosed:
        case RawSocketEvent.closed:
          cleanUp();
          print('Client Socket closed');
          break;
      }
    }, onError: (e) {
      print('Error: $e');
      cleanUp();
    }, onDone: () {
      print('Connection done');
      cleanUp();
    });
  }


  void writeChunked(RawSecureSocket socket, List<int> data) {
    _writeQueue.add(data);
    if (!_waitingToWrite) {
      _flush();
    }
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

}