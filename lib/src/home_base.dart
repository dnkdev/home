import 'dart:io';
import 'dart:async';
// import 'dart:convert';
// import 'dart:typed_data';
// import 'dart:collection' show Queue;
import 'dart:isolate';
import 'package:synchronized/synchronized.dart';
// import 'package:http2/src/hpack/hpack.dart';
import 'package:home/log.dart';
import 'package:home/client.dart';
import 'package:home/client_raw.dart';


Lock fileIoLock = Lock();

class ClientSecurityContext {
  RawSocket socket;
  SecurityContext? context;
  StreamSubscription<RawSocketEvent>? subscription;
  List<int>? bufferedData;
  bool requestClientCertificate = false;
  bool requireClientCertificate = false;
  List<String>? supportedProtocols;

  ClientSecurityContext(
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

/// to pass info to every isolate, the options is decoupled from SecurityContext
class StartOptions {
  final String certPath;
  final String keyPath;
  final bool shared;
  final bool requestClientCert;
  final bool requireClientCert;
  final List<String> protocols;
  final List<int>? bufferedData;
  final SendPort mainSendPort;
  final bool useTLS;
  final LogLevel logLevel;

  const StartOptions(this.mainSendPort, {
    required this.certPath,
    required this.keyPath,
    this.shared = false,
    this.requestClientCert = false,
    this.requireClientCert = false,
    this.protocols = const ['http1.1'],
    this.bufferedData,
    this.useTLS = true,
    this.logLevel = LogLevel.debug
  });

  Map<String, dynamic> toMap() => {
    'logLevel': logLevel,
    'useTLS': useTLS,
    'mainSendPort': mainSendPort,
    'certPath': certPath,
    'keyPath': keyPath,
    'shared': shared,
    'requestClientCert': requestClientCert,
    'requireClientCert': requireClientCert,
    'protocols': protocols,
  };

  static StartOptions fromMap(Map<String, dynamic> map) {
    return StartOptions(
      map['mainSendPort'],
      logLevel: map['logLevel'],
      useTLS: map['useTLS'],
      certPath: map['certPath'],
      keyPath: map['keyPath'],
      shared: map['shared'] ?? false,
      requestClientCert: map['requestClientCert'] ?? false,
      requireClientCert: map['requireClientCert'] ?? false,
      protocols: List<String>.from(map['protocols'] ?? ['http1.1']),
    );
  }

  static SecurityContext? createContext(StartOptions? data) {
    if (data == null) return null;
    final context = SecurityContext()
      ..useCertificateChain(data.certPath)
      ..usePrivateKey(data.keyPath)
      ..setAlpnProtocols(data.protocols, true);

      
    return context;
  }
  static ClientSecurityContext? createClientContext(RawSocket socket, StartOptions? data) {
    if (data == null) return null;
    final context = SecurityContext()
      ..useCertificateChain(data.certPath)
      ..usePrivateKey(data.keyPath)
      ..setAlpnProtocols(data.protocols, true);

      
    return ClientSecurityContext(socket, context,
      requestClientCertificate: data.requestClientCert,
      requireClientCertificate: data.requireClientCert,
      supportedProtocols: data.protocols,
      bufferedData: data.bufferedData
    );
  }

  factory StartOptions.defaultOpt(SendPort mainSendPort, {bool shared = false, bool useTLS = true, LogLevel logLevel = LogLevel.debug}) {
    return StartOptions(
      mainSendPort,
      logLevel: logLevel,
      useTLS: useTLS,
      certPath: 'cert.pem',
      keyPath: 'priv.pem',
      protocols: ['http1.1'],
      shared: shared,
    );
  }

}

class RawServer {
  final InternetAddress address;
  final int port;
  late RawServerSocket _server;
  final List<SendPort> workerPorts = [];

  RawServer(this.address, this.port);


  Future<void> start(StartOptions? startOpt) async{
    if (startOpt?.shared == true) {
      await _startMultiThreaded(startOpt: startOpt);
    } else {
      if(startOpt?.useTLS == true) {
        await _startServer(startOpt!.toMap());
        return;
      }
      await _startHttpServer(startOpt!.toMap());
    }
  }
  Future<void> _startHttpServer(Map<String, dynamic>? startOptMap) async {
   
    final opt = StartOptions.fromMap(startOptMap!); 
    print(opt.shared);
    _server = await RawServerSocket.bind(address, port, shared: opt.shared);
    Log.info(()=>'Server listening on $address:$port');

    _server.listen((rawSocket) async {
        final client = ClientRaw(rawSocket); 
        client.handleConnection();

    });
  }
  /// Starts listening with the specified security contexts. ClientSecurityContext wraps `RawSecureSocket.secureServer(...)` method,
  /// which is used to proceed TLS handshake client with server.
  Future<void> _startServer(Map<String, dynamic>? startOpt) async {

    final opt = StartOptions.fromMap(startOpt!);
    final context = StartOptions.createContext(opt);
    
    final workerPort = ReceivePort();
    if (opt.shared){
      workerPort.listen((data) {
        Log.info(()=>'Isolate ${Isolate.current.hashCode} received : $data');
      });
    }
    // final context = startOpt?.secContext ?? SecurityContext()
    //   ..setAlpnProtocols(['http1.1'], true)
    //   ..useCertificateChain('cert.pem')
    //   ..usePrivateKey('priv.pem');

    if (context == null)  throw Exception('Security Context is Null');

    _server = await RawServerSocket.bind(address, port, shared: opt.shared);
    // Log.info(()=>'Server listening on $address:$port');

    _server.listen((rawSocket) async {
      // opt.mainSendPort.send(['Hello Bro', workerPort.sendPort]);
      // Log.debug(()=>'Client conected on ${Isolate.current.hashCode}');
      Log.debug(()=>'[${rawSocket.remoteAddress.address}:${rawSocket.remotePort}] Client connected ');

      
      RawSecureSocket? secureSocket;
      try {
        // final secClientOptions = StartOptions.createClientContext(rawSocket, opt);
        // secureSocket = secClientOptions != null ? await secClientOptions.secure() : await ClientSecurityContext(rawSocket, context, supportedProtocols: ['http1.1']).secure();
        secureSocket = await ClientSecurityContext(rawSocket, context, 
          supportedProtocols: opt.protocols,
          bufferedData: opt.bufferedData,
          requestClientCertificate: opt.requestClientCert,
          requireClientCertificate: opt.requireClientCert,
        ).secure();
        // secureSocket = await RawSecureSocket.secureServer(
        //   rawSocket,
        //   context, 
        //   // subscription:  opt., 
        //   bufferedData:  opt.bufferedData, 
        //   requestClientCertificate:  opt.requestClientCert, 
        //   requireClientCertificate:  opt.requireClientCert, 
        //   supportedProtocols: opt.protocols
        // );


        Log.debug(() => 'ALPN selected protocol: ${secureSocket!.selectedProtocol}');
        Log.debug(() => '[${secureSocket!.remoteAddress.address}:${secureSocket.remotePort}] TLS handshake completed');
      } 
      catch (e,s) {
        Log.error(()=>'[${rawSocket.remoteAddress.address}:${rawSocket.remotePort}] TLS handshake failed: $e: $s');
        rawSocket.close();
        return;
      }
      Client client = Client(secureSocket, rawSocket.remoteAddress.address, rawSocket.remotePort);
      // client.handleSocket();
      // preface();
      // handleHttp2Preface(secureSocket);
      client.handleConnection();
    });
  }

  void isolateEntry(Map<String, dynamic> rawOptions) async{
    Log.debug(()=>'Isolate started on ${Isolate.current.hashCode}');
    Log.level = rawOptions['logLevel']; 
    // final opt = StartOptions.fromMap(rawOptions);
    final server = RawServer(InternetAddress.anyIPv4, 443);
    if(rawOptions['useTLS'] == true) {
      await _startServer(rawOptions);
      return;
    }else {
      await server._startHttpServer(rawOptions); // already a Map
    }
  }

  Future<void> _startMultiThreaded({StartOptions? startOpt}) async {
    final cpuCount = Platform.numberOfProcessors;
    Log.debug(()=> 'Starting multithreaded $cpuCount');
    for (int i = 0; i < cpuCount; i++) {
      await Isolate.spawn(isolateEntry, startOpt!.toMap());
    }
  }

  Future<void> close() async {
    await _server.close();
  }
}
