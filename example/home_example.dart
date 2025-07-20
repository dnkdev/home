import 'package:home/home.dart';
import 'dart:io';


void main() async {
  await RawServer(InternetAddress.anyIPv4, 443).start();

  final addresses = await InternetAddress.lookup('google.com');
  for (final address in addresses) {
    print('Found address: ${address.address} (type: ${address.type})');
  }
}