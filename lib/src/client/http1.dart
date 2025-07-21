part of 'client.dart';

class Http1Request {
  final String method;
  final String path;
  final String version;
  final Map<String, String> headers;
  final Uint8List? body;

  Http1Request(this.method, this.path, this.version, this.headers, this.body);
}
