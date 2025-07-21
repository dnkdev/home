part of 'client.dart';

class Http1Request {
  final String method;
  final String path;
  final String version;
  final Map<String, String> headers;
  List<int> body;
  final Completer<void> bodyComplete = Completer<void>();

  Http1Request(this.method, this.path, this.version, this.headers, [this.body = const []]);

  int get contentLength => int.tryParse(headers['content-length'] ?? '') ?? 0;
  bool get hasBody => contentLength > 0;

  Future<void> waitForBody() => bodyComplete.future;
}