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
import 'package:home/cache.dart';
import 'package:home/utils.dart';


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
/// 
/// [shared] multithreaded or not
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

class Server {
  final InternetAddress address;
  final int port;
  late RawServerSocket _server;
  final List<SendPort> workerPorts = [];

  Server(this.address, this.port);


  Future<void> start(StartOptions? startOpt) async{
    Log.info(()=>'Listenning on $address:$port ${startOpt != null ? (startOpt.shared ? 'shared: ${startOpt.shared} ${Platform.numberOfProcessors}' : '') :''} ${startOpt?.protocols}');
    if (startOpt?.shared == true) {
      await _startMultiThreaded(startOpt: startOpt);
    } else {
      await _startServer(startOpt!.toMap()); 
    }
  }

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

    _server.listen((rawSocket) async {
      final ip = rawSocket.remoteAddress.address;
      final remotePort = rawSocket.remotePort;
      // opt.mainSendPort.send(['Hello Bro', workerPort.sendPort]);
      // Log.debug(()=>'Client conected on ${Isolate.current.hashCode}');
      Log.debug(()=>'[$ip:$remotePort] Client connected ');
      
      
      RawSecureSocket? secureSocket;
      try {
        // final secClientOptions = StartOptions.createClientContext(rawSocket, opt);
        // secureSocket = secClientOptions != null ? await secClientOptions.secure() : await ClientSecurityContext(rawSocket, context, supportedProtocols: ['http1.1']).secure();
        // secureSocket = await ClientSecurityContext(rawSocket, context, 
        //   supportedProtocols: opt.protocols,
        //   bufferedData: opt.bufferedData,
        //   requestClientCertificate: opt.requestClientCert,
        //   requireClientCertificate: opt.requireClientCert,
        // ).secure();
        secureSocket = await RawSecureSocket.secureServer(
          rawSocket,
          context, 
          // subscription:  opt., 
          bufferedData:  opt.bufferedData, 
          requestClientCertificate:  opt.requestClientCert, 
          requireClientCertificate:  opt.requireClientCert, 
          supportedProtocols: opt.protocols
        );


        // Log.debug(() => 'ALPN selected protocol: ${secureSocket!.selectedProtocol}');
      } 
      catch (e,s) {
        Log.error(()=>'[$ip:$remotePort] TLS handshake failed: $e: $s');
        await rawSocket.close();
        return;
      }
      Client client = Client(secureSocket, rawSocket.remoteAddress.address, rawSocket.remotePort);
      Log.debug(() => '[${client.ip}:${client.remotePort}] TLS handshake completed [ALPN: ${secureSocket != null ? secureSocket.selectedProtocol : "no"}]');
      // client.handleSocket();
      // preface();
      // handleHttp2Preface(secureSocket);
      client.handleConnection();
    });
  }

  void isolateEntry(Map<String, dynamic> rawOptions) async{
    Log.level = rawOptions['logLevel']; 
    final server = Server(InternetAddress.anyIPv4, port);
    await server._startServer(rawOptions);
  }

  Future<void> _startMultiThreaded({StartOptions? startOpt}) async {
    final cpuCount = Platform.numberOfProcessors;
    for (int i = 0; i < cpuCount; i++) {
      await Isolate.spawn(isolateEntry, startOpt!.toMap());
    }
  }

  Future<void> close() async {
    await _server.close();
  }


  static Future<String> file(String filePath, {bool normalize = true, Duration? ttl}) async {
    return await fileIoLock.synchronized(() async {
      final normalizedPath = normalize ? await normalizeDirPath(
        filePath,
        allowedDir: Directory.current.path,
      ) : filePath;

      Log.debug(()=>'file($filePath, $normalize, $ttl) looking $normalizedPath');

      if (FileCache.cache[normalizedPath] != null){
        if(FileCache.cache[normalizedPath]!.isValid) {
          Log.debug(()=> 'Returning cached value $normalizedPath');
          return FileCache.cache[normalizedPath]!.content!;
        }
        else {
          FileCache.cache[normalizedPath]!.clear();
        }
      }
     
      Log.debug(()=> 'Caching page $normalizedPath'); 
      final file = File(normalizedPath);
      final content = await file.readAsString();
      FileCache.set(normalizedPath, CacheItem(content , ttl: ttl));
     
      return  FileCache.get(normalizedPath)!.content!;
    });
  }
  
  static Future<List<int>> fileBin(String filePath, {bool normalize = false, Duration? ttl}) async {
    return await fileIoLock.synchronized(() async {
      final normalizedPath = normalize ? await normalizeDirPath(
        filePath,
        allowedDir: Directory.current.path,
      ) : filePath;

      Log.debug(()=>'file($filePath, $normalize, $ttl) looking $normalizedPath');

      if (BinFileCache.cache[normalizedPath] != null){
        if(BinFileCache.cache[normalizedPath]!.isValid) {
          Log.debug(()=> 'Returning cached value $normalizedPath');
          return BinFileCache.cache[normalizedPath]!.content!;
        }
        else {
          BinFileCache.cache[normalizedPath]!.clear();
        }
      }
     
      Log.debug(()=> 'Caching page $normalizedPath'); 
      final file = File(normalizedPath);
      final content = await file.readAsBytes();
      BinFileCache.set(normalizedPath, CacheItem(content , ttl: ttl));
     
      return  BinFileCache.get(normalizedPath)!.content!;
    });
  }

}
