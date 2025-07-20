import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:collection' show Queue;
import 'package:synchronized/synchronized.dart';
import 'package:http2/src/hpack/hpack.dart';
import 'package:home/response.dart';
import 'package:home/log.dart';
import 'package:home/models.dart';
import 'package:home/http2.dart';

part 'client_base.dart';
part 'bytebuffer.dart';

Lock fileIoLock = Lock();

// class RawSecureSocketWrapper {
//   final RawSecureSocket _socket;
//   final StreamController<List<int>> _controller = StreamController();
//   final Queue<List<int>> _writeQueue = Queue<List<int>>();
//   bool _waitingToWrite = false;
//   bool _isClosed = false;

//   RawSecureSocketWrapper(this._socket) {
//     _socket.listen(_handleEvent, onError: _handleError, onDone: _handleDone);
//   }

//   Stream<List<int>> get stream => _controller.stream;

//   void write(List<int> data) {
//     if (_isClosed) return;
//     _writeQueue.add(data);
//     if (!_waitingToWrite) _flush();
//   }

//   void _flush() {
//     if (_isClosed) {
//       _writeQueue.clear();
//       _waitingToWrite = false;
//       return;
//     }
//     while (_writeQueue.isNotEmpty) {
//       final chunk = _writeQueue.removeFirst();
//       final written = _socket.write(chunk);
//       if (written < chunk.length) {
//         _writeQueue.addFirst(chunk.sublist(written));
//         _waitingToWrite = true;
//         return;
//       }
//     }
//     _waitingToWrite = false;
//   }

//   void _handleEvent(RawSocketEvent event) {
//     switch (event) {
//       case RawSocketEvent.read:
//         final data = _socket.read();
//         if (data != null) {
//           _controller.add(data);
//         }
//         break;
//       case RawSocketEvent.write:
//         _flush();
//         break;
//       case RawSocketEvent.readClosed:
//       case RawSocketEvent.closed:
//         _isClosed = true;
//         _controller.close();
//         break;
//     }
//   }

//   void _handleError(Object error) {
//     _controller.addError(error);
//     close();
//   }

//   void _handleDone() {
//     _isClosed = true;
//     _controller.close();
//   }

//   Future<void> close() async {
//     if (_isClosed) return;
//     _isClosed = true;
//     await _controller.close();
//     _socket.close();
//   }
// }

class SetSecureOnRaw {
  RawSocket socket;
  SecurityContext? context;
  StreamSubscription<RawSocketEvent>? subscription;
  List<int>? bufferedData;
  bool requestClientCertificate = false;
  bool requireClientCertificate = false;
  List<String>? supportedProtocols;

  SetSecureOnRaw(
    this.socket, 
    this.context, {
    this.subscription, 
    this.bufferedData, 
    this.requestClientCertificate = false, 
    this.requireClientCertificate = false, 
    this.supportedProtocols
  });

  Future<RawSecureSocket> secure() async{
    return await RawSecureSocket.secureServer(
          socket,
          context, 
          subscription:  subscription, 
          bufferedData:  bufferedData, 
          requestClientCertificate:  requestClientCertificate, 
          requireClientCertificate:  requireClientCertificate, 
          supportedProtocols: supportedProtocols
        );
  }
}


class RawServer {
  final InternetAddress address;
  final int port;
  late RawServerSocket _server;

  RawServer(this.address, this.port);

  /// Starts listening with the specified security contexts. SetSecureOnRaw wraps `RawSecureSocket.secureServer(...)` method,
  /// which is used to proceed TLS handshake with client.
  Future<void> start({SecurityContext? secContext, SetSecureOnRaw? secClientOptions}) async {

    var context = secContext ?? SecurityContext()
      ..setAlpnProtocols(['h2'], true)
      ..useCertificateChain('cert.pem')
      ..usePrivateKey('priv.pem');


    _server = await RawServerSocket.bind(address, port);
    print('Server listening on $address:$port');

    _server.listen((rawSocket) async {
      Log.debug(()=>'Client connected ${rawSocket.remoteAddress.address}:${rawSocket.remotePort}');

      RawSecureSocket? secureSocket;
      try {
        secureSocket = secClientOptions != null ? await secClientOptions.secure() : await SetSecureOnRaw(rawSocket, context, supportedProtocols: ['h2']).secure();
        
        print('ALPN selected protocol: ${secureSocket.selectedProtocol}');
        Log.debug(() => 'TLS handshake completed with ${secureSocket!.remoteAddress.address}:${secureSocket.remotePort}');
      } 
      catch (e,s) {
        rawSocket.close();
        print('TLS handshake failed: $e: $s');
        return;
      }
      Client client = Client(secureSocket);
      // client.handleSocket();
      // preface();
      // handleHttp2Preface(secureSocket);
      client.handleConnection();
    });
  }

  
  Future<void> parseHeaders(Client client, String fullRequest) async {
    if (fullRequest.isNotEmpty) {//.contains('\r\n\r\n')) {
        final lines = fullRequest.split('\r\n');
        if (lines.isEmpty ) client.reject(soft:false);
        final requestLine = lines.first;
        print('Request line: $requestLine');

        final parts = requestLine.split(' ');
        final method = parts[0];
        final path = parts.length > 1 ? parts[1] : '/';
        print('$parts, $method, $path');
        for (var line in lines){
          print('Rest: $line');
        }
    }
  }

  Future<Response> makeResponse(String content)async {
    
    
    return Response.ok(content);
  }

  // void handleConnection(Socket socket) {
  //   final buffer = StringBuffer();

  //   socket.listen(
  //     (data) async {
  //       buffer.write(String.fromCharCodes(data));

  //       final fullRequest = buffer.toString();
  //       await parseHeaders(socket, fullRequest);
  //       var response = await makeResponse('OK');
  //       await response.socksend(socket);
  //       // socket.write(response);
  //       socket.flush().then((_) => socket.destroy());
  //     }, 
  //     onDone: () => socket.destroy(),
  //   );
  // }

  Future<void> close() async {
    await _server.close();
  }
}
