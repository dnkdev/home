import 'package:home/log.dart';
import 'package:home/home.dart';
import 'package:home/router.dart';
import 'package:home/models.dart';
import 'package:home/response.dart';
import 'dart:io';
import 'dart:isolate';



void main() async {
  final mainPort = ReceivePort();
  final mainSendPort = mainPort.sendPort;
  await Server(InternetAddress.anyIPv4, 443)
    .start(
      StartOptions.defaultOpt(mainSendPort, shared: true, useTLS: true, logLevel: LogLevel.debug)
    );

  AddRoute(
    HtmlRoute(
      method: Method.GET,
      urlPath: '/',
      clientHandler: (client) async {
        Response.ok('You are good bro!').send(client);
      }
    )
  );

  // final addresses = await InternetAddress.lookup('google.com');
  // for (final address in addresses) {
  //   print('Found address: ${address.address} (type: ${address.type})');
  // }


  // Main isolate listening for messages from spawned Isolates
  // await for (final k in mainPort) {
  //   // print('KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK = \n${k[0]}');
  //   // print(k[1]);
  //   // k[1].send('Ponging back: ${k[0]}');
  // }
}