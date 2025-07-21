import 'package:home/log.dart';
import 'package:home/home.dart';
import 'dart:io';
import 'dart:isolate';


void main() async {
  final mainPort = ReceivePort();
  final mainSendPort = mainPort.sendPort;
  await RawServer(InternetAddress.anyIPv4, 443)
    .start(StartOptions.defaultOpt(mainSendPort, shared: true, useTLS: true, logLevel: LogLevel.error));

  final addresses = await InternetAddress.lookup('google.com');
  for (final address in addresses) {
    print('Found address: ${address.address} (type: ${address.type})');
  }


  // Main isolate listening for messages from spawned Isolates
  // await for (final k in mainPort) {
  //   // print('KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK = \n${k[0]}');
  //   // print(k[1]);
  //   // k[1].send('Ponging back: ${k[0]}');
  // }
}