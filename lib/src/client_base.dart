part of 'home_base.dart';

/*
class ClientOld with IClientImplemented {
  @override
  Method? method;
  @override
  String? url;

  final String ip;
  final int remotePort;
  final BytesBuilder _buffer = BytesBuilder();

  ClientOld(this._socket) : ip = _socket.remoteAddress.address, remotePort = _socket.remotePort;



void onRequest(String rawHeaders, Map<String, String> headers, String body) {
  print('Parsed Headers:\n$rawHeaders');
  print('Body: $body');

  const response = 'HTTP/1.1 200 OK\r\n'
      'Content-Type: text/plain\r\n'
      'Content-Length: 3\r\n'
      '\r\n'
      'OK!';

  socket.write(utf8.encode(response));
  socket.close();
}
int getContentLength(Map<String, String> headers) {
  final length = headers['content-length'];
  return length != null ? int.tryParse(length) ?? 0 : 0;
}
Map<String, String> parseHeaders(String headerText) {
  final lines = headerText.split('\r\n');
  final headers = <String, String>{};

  for (var i = 1; i < lines.length; i++) {
    final parts = lines[i].split(':');
    if (parts.length >= 2) {
      final name = parts[0].trim().toLowerCase();
      final value = parts.sublist(1).join(':').trim();
      headers[name] = value;
    }
  }

  return headers;
}
void tryParseRequest() {
  final bytes = _buffer.toBytes();
  final text = utf8.decode(bytes, allowMalformed: true);
  final headerEnd = text.indexOf('\r\n\r\n');

  if (headerEnd == -1) return; // Headers not complete

  final headerText = text.substring(0, headerEnd);
  final headers = parseHeaders(headerText);
  final contentLength = getContentLength(headers);

  final totalLength = headerEnd + 4 + contentLength;
  if (bytes.length < totalLength) return; // Full body not yet received

  final bodyBytes = bytes.sublist(headerEnd + 4, totalLength);
  final body = utf8.decode(bodyBytes, allowMalformed: true);

  onRequest(headerText, headers, body);

  // Remove handled bytes from buffer
  final remaining = bytes.sublist(totalLength);
  _buffer.clear();
  _buffer.add(remaining);
}

  void handleSocket() {
    // print('Secure connection from ${socket.remoteAddress.address}:${socket.remotePort}');

    socket.listen((event) {
      switch (event) {
        case RawSocketEvent.read:
          final data = socket.read();
          if (data != null) _buffer.add(data);
          tryParseRequest();
          break;

        case RawSocketEvent.write:
          _flush();
          break;

        case RawSocketEvent.readClosed:
        case RawSocketEvent.closed:
          print('Client Socket closed');
          cleanUp();
          break;
      }
    }, onError: (e) {
      print('Client Socket error: $e');
      cleanUp();
    }, onDone: () {
      print('Client Socket done');
      cleanUp();
    });
  }

  void handleIncoming() {
    print('Secure connection from ${socket.remoteAddress.address}:${socket.remotePort}');
    final buffer = BytesBuilder();

    socket.listen((event) async {
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


}
*/